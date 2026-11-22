import 'dart:async';
import 'dart:convert';
import 'package:dartz/dartz.dart';
import 'package:drift/drift.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/features/feature_gate.dart';
import '../../domain/entities/telegram_inbox_message_entity.dart';
import 'telegram_message_parser.dart';

class TelegramBotService {
  final AppDatabase _db;
  final FeatureGate _featureGate;
  final _uuid = const Uuid();
  bool _initialized = false;

  TelegramBotService(this._db, this._featureGate);

  Future<void> ensureTableExists() async {
    if (_initialized) return;

    await _db.customStatement('''
      CREATE TABLE IF NOT EXISTS telegram_inbox_messages (
        id TEXT PRIMARY KEY,
        update_id INTEGER NOT NULL,
        message_id INTEGER NOT NULL,
        chat_id TEXT NOT NULL,
        sender_name TEXT NOT NULL,
        sender_username TEXT,
        message_text TEXT NOT NULL,
        extracted_links TEXT,
        extracted_size TEXT,
        extracted_color TEXT,
        extracted_qty INTEGER NOT NULL DEFAULT 1,
        extracted_sku TEXT,
        status TEXT NOT NULL DEFAULT 'pending',
        created_at INTEGER NOT NULL,
        processed_at INTEGER
      );
    ''');

    _initialized = true;
  }

  Future<String?> getBotToken() async {
    return _featureGate.getMeta('telegram.bot_token');
  }

  Future<void> saveBotToken(String token, {required String userId}) async {
    await _featureGate.setMeta('telegram.bot_token', token.trim(), userId: userId);
  }

  Future<String?> getBotUsername() async {
    return _featureGate.getMeta('telegram.bot_username');
  }

  Future<void> saveBotUsername(String username, {required String userId}) async {
    await _featureGate.setMeta('telegram.bot_username', username.trim(), userId: userId);
  }

  /// Verifies if the bot token is valid via Telegram API getMe
  Future<Either<String, Map<String, dynamic>>> testBotToken(String token) async {
    final cleanToken = token.trim();
    if (cleanToken.isEmpty) {
      return const Left('يرجى إدخال توكن البوت');
    }

    try {
      final uri = Uri.parse('https://api.telegram.org/bot$cleanToken/getMe');
      final res = await http.get(uri).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        if (body['ok'] == true && body['result'] != null) {
          final result = body['result'] as Map<String, dynamic>;
          return Right(result);
        } else {
          return Left(body['description']?.toString() ?? 'فشل التحقق من التوكن');
        }
      } else {
        try {
          final body = jsonDecode(res.body) as Map<String, dynamic>;
          return Left(body['description']?.toString() ?? 'خطأ في الاتصال بالبوت (${res.statusCode})');
        } catch (_) {
          return Left('خطأ في الاتصال بسيرفر تيليجرام (${res.statusCode})');
        }
      }
    } catch (e) {
      return Left('تعذر الاتصال بتيليجرام: $e');
    }
  }

  /// Pulls new messages directly and freely from Telegram Bot API getUpdates
  Future<Either<String, int>> fetchNewMessages() async {
    await ensureTableExists();

    final token = await getBotToken();
    if (token == null || token.trim().isEmpty) {
      return const Left('لم يتم ضبط توكن بوت تيليجرام في الإعدادات');
    }

    try {
      // Find highest update_id saved locally
      final maxRow = await _db.customSelect(
        'SELECT MAX(update_id) as max_id FROM telegram_inbox_messages;',
      ).getSingleOrNull();

      final maxId = maxRow?.data['max_id'];
      final int lastUpdateId = maxId is int ? maxId : (maxId != null ? int.tryParse(maxId.toString()) ?? 0 : 0);
      final offset = lastUpdateId > 0 ? lastUpdateId + 1 : 0;

      final uri = Uri.parse('https://api.telegram.org/bot${token.trim()}/getUpdates?offset=$offset&limit=100');
      final res = await http.get(uri).timeout(const Duration(seconds: 15));

      if (res.statusCode != 200) {
        return Left('خطأ من خادم تيليجرام (${res.statusCode})');
      }

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (body['ok'] != true || body['result'] == null) {
        return Left(body['description']?.toString() ?? 'فشل سحب التحديثات');
      }

      final updates = body['result'] as List<dynamic>;
      int insertedCount = 0;

      for (final u in updates) {
        if (u is! Map<String, dynamic>) continue;
        final updateId = u['update_id'] as int? ?? 0;

        final msg = (u['message'] ?? u['channel_post'] ?? u['edited_message']) as Map<String, dynamic>?;
        if (msg == null) continue;

        final messageId = msg['message_id'] as int? ?? 0;
        final from = msg['from'] as Map<String, dynamic>?;
        final chat = msg['chat'] as Map<String, dynamic>? ?? {};

        final senderFirstName = from?['first_name']?.toString() ?? chat['title']?.toString() ?? 'عميل تيليجرام';
        final senderLastName = from?['last_name']?.toString() ?? '';
        final senderName = ('$senderFirstName $senderLastName').trim();
        final senderUsername = from?['username']?.toString() ?? chat['username']?.toString();
        final chatId = chat['id']?.toString() ?? from?['id']?.toString() ?? '';

        final text = msg['text']?.toString() ?? msg['caption']?.toString() ?? '';
        if (text.trim().isEmpty) continue;

        // Skip bot's own messages or commands like /start without content
        if (from?['is_bot'] == true) continue;

        final parsed = TelegramMessageParser.parse(text);

        final msgDateUnix = msg['date'] as int?;
        final createdAtMillis = msgDateUnix != null
            ? msgDateUnix * 1000
            : DateTime.now().millisecondsSinceEpoch;

        final rowId = _uuid.v4();

        await _db.customInsert(
          '''
          INSERT OR IGNORE INTO telegram_inbox_messages (
            id, update_id, message_id, chat_id, sender_name, sender_username,
            message_text, extracted_links, extracted_size, extracted_color,
            extracted_qty, extracted_sku, status, created_at
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', ?);
          ''',
          variables: [
            Variable.withString(rowId),
            Variable.withInt(updateId),
            Variable.withInt(messageId),
            Variable.withString(chatId),
            Variable.withString(senderName),
            Variable.withString(senderUsername ?? ''),
            Variable.withString(text),
            Variable.withString(jsonEncode(parsed.links)),
            Variable.withString(parsed.size ?? ''),
            Variable.withString(parsed.color ?? ''),
            Variable.withInt(parsed.qty),
            Variable.withString(parsed.sku ?? ''),
            Variable.withInt(createdAtMillis),
          ],
        );

        insertedCount++;
      }

      return Right(insertedCount);
    } catch (e) {
      return Left('خطأ أثناء سحب رسائل تيليجرام: $e');
    }
  }

  /// Get inbox messages ordered by createdAt DESC
  Future<List<TelegramInboxMessageEntity>> getMessages({String? status, String? searchQuery}) async {
    await ensureTableExists();

    var sql = 'SELECT * FROM telegram_inbox_messages';
    final conditions = <String>[];
    final variables = <Variable>[];

    if (status != null && status.isNotEmpty && status != 'all') {
      conditions.add('status = ?');
      variables.add(Variable.withString(status));
    }

    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      conditions.add('(sender_name LIKE ? OR sender_username LIKE ? OR message_text LIKE ? OR extracted_sku LIKE ?)');
      final term = '%${searchQuery.trim()}%';
      variables.addAll([
        Variable.withString(term),
        Variable.withString(term),
        Variable.withString(term),
        Variable.withString(term),
      ]);
    }

    if (conditions.isNotEmpty) {
      sql += ' WHERE ${conditions.join(' AND ')}';
    }

    sql += ' ORDER BY created_at DESC;';

    final rows = await _db.customSelect(sql, variables: variables).get();

    return rows.map((r) {
      final linksJson = r.data['extracted_links']?.toString() ?? '[]';
      List<String> links = [];
      try {
        final decoded = jsonDecode(linksJson);
        if (decoded is List) {
          links = decoded.map((e) => e.toString()).toList();
        }
      } catch (_) {}

      final createdAtMillis = r.data['created_at'] as int? ?? DateTime.now().millisecondsSinceEpoch;
      final processedAtMillis = r.data['processed_at'] as int?;

      return TelegramInboxMessageEntity(
        id: r.data['id'].toString(),
        updateId: r.data['update_id'] as int? ?? 0,
        messageId: r.data['message_id'] as int? ?? 0,
        chatId: r.data['chat_id']?.toString() ?? '',
        senderName: r.data['sender_name']?.toString() ?? 'عميل',
        senderUsername: r.data['sender_username']?.toString().isNotEmpty == true
            ? r.data['sender_username']?.toString()
            : null,
        messageText: r.data['message_text']?.toString() ?? '',
        extractedLinks: links,
        extractedSize: r.data['extracted_size']?.toString().isNotEmpty == true
            ? r.data['extracted_size']?.toString()
            : null,
        extractedColor: r.data['extracted_color']?.toString().isNotEmpty == true
            ? r.data['extracted_color']?.toString()
            : null,
        extractedQty: r.data['extracted_qty'] as int? ?? 1,
        extractedSku: r.data['extracted_sku']?.toString().isNotEmpty == true
            ? r.data['extracted_sku']?.toString()
            : null,
        status: r.data['status']?.toString() ?? 'pending',
        createdAt: DateTime.fromMillisecondsSinceEpoch(createdAtMillis),
        processedAt: processedAtMillis != null
            ? DateTime.fromMillisecondsSinceEpoch(processedAtMillis)
            : null,
      );
    }).toList();
  }

  /// Returns count of pending unhandled messages
  Future<int> getPendingCount() async {
    await ensureTableExists();
    final row = await _db.customSelect(
      "SELECT COUNT(*) as cnt FROM telegram_inbox_messages WHERE status = 'pending';",
    ).getSingleOrNull();

    final cnt = row?.data['cnt'];
    if (cnt is int) return cnt;
    return int.tryParse(cnt?.toString() ?? '0') ?? 0;
  }

  /// Update message status ('converted' or 'archived')
  Future<void> markMessageStatus(String messageId, String status) async {
    await ensureTableExists();
    final nowMillis = DateTime.now().millisecondsSinceEpoch;
    await _db.customUpdate(
      'UPDATE telegram_inbox_messages SET status = ?, processed_at = ? WHERE id = ?;',
      variables: [
        Variable.withString(status),
        Variable.withInt(nowMillis),
        Variable.withString(messageId),
      ],
    );
  }

  /// Delete message from inbox
  Future<void> deleteMessage(String messageId) async {
    await ensureTableExists();
    await _db.customUpdate(
      'DELETE FROM telegram_inbox_messages WHERE id = ?;',
      variables: [Variable.withString(messageId)],
    );
  }
}
