import 'package:equatable/equatable.dart';

class TelegramInboxMessageEntity extends Equatable {
  final String id;
  final int updateId;
  final int messageId;
  final String chatId;
  final String senderName;
  final String? senderUsername;
  final String messageText;
  final List<String> extractedLinks;
  final String? extractedSize;
  final String? extractedColor;
  final int extractedQty;
  final String? extractedSku;
  final String status; // 'pending', 'converted', 'archived'
  final DateTime createdAt;
  final DateTime? processedAt;

  const TelegramInboxMessageEntity({
    required this.id,
    required this.updateId,
    required this.messageId,
    required this.chatId,
    required this.senderName,
    this.senderUsername,
    required this.messageText,
    this.extractedLinks = const [],
    this.extractedSize,
    this.extractedColor,
    this.extractedQty = 1,
    this.extractedSku,
    this.status = 'pending',
    required this.createdAt,
    this.processedAt,
  });

  bool get isPending => status == 'pending';
  bool get isConverted => status == 'converted';
  bool get isArchived => status == 'archived';

  TelegramInboxMessageEntity copyWith({
    String? id,
    int? updateId,
    int? messageId,
    String? chatId,
    String? senderName,
    String? senderUsername,
    String? messageText,
    List<String>? extractedLinks,
    String? extractedSize,
    String? extractedColor,
    int? extractedQty,
    String? extractedSku,
    String? status,
    DateTime? createdAt,
    DateTime? processedAt,
  }) {
    return TelegramInboxMessageEntity(
      id: id ?? this.id,
      updateId: updateId ?? this.updateId,
      messageId: messageId ?? this.messageId,
      chatId: chatId ?? this.chatId,
      senderName: senderName ?? this.senderName,
      senderUsername: senderUsername ?? this.senderUsername,
      messageText: messageText ?? this.messageText,
      extractedLinks: extractedLinks ?? this.extractedLinks,
      extractedSize: extractedSize ?? this.extractedSize,
      extractedColor: extractedColor ?? this.extractedColor,
      extractedQty: extractedQty ?? this.extractedQty,
      extractedSku: extractedSku ?? this.extractedSku,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      processedAt: processedAt ?? this.processedAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        updateId,
        messageId,
        chatId,
        senderName,
        senderUsername,
        messageText,
        extractedLinks,
        extractedSize,
        extractedColor,
        extractedQty,
        extractedSku,
        status,
        createdAt,
        processedAt,
      ];
}

