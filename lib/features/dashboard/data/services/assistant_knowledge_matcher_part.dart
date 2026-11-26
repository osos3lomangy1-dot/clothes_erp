part of 'offline_smart_assistant_service.dart';
/// Offline synonym + fuzzy scoring matcher over `assets/assistant_knowledge_ar.json`.
class OfflineKnowledgeMatcher {
  _AssistantKnowledgeBase? _cachedKnowledgeBase;

  Future<_AssistantKnowledgeBase> _loadKnowledgeBase() async {
    if (_cachedKnowledgeBase != null) return _cachedKnowledgeBase!;
    try {
      final raw = await rootBundle.loadString('assets/assistant_knowledge_ar.json');
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      _cachedKnowledgeBase = _AssistantKnowledgeBase.fromJson(decoded);
      return _cachedKnowledgeBase!;
    } catch (_) {
      return const _AssistantKnowledgeBase(synonymGroups: [], topics: []);
    }
  }

  Future<int> topicCount() async {
    final kb = await _loadKnowledgeBase();
    return kb.topics.length;
  }

  static const _arabicStopWords = <String>{
    'في',
    'من',
    'على',
    'عن',
    'الى',
    'مع',
    'هذا',
    'هذه',
    'التي',
    'الذي',
    'غير',
    'كل',
    'او',
    'ان',
    'لو',
    'ما',
    'لا',
    'هل',
    'عند',
    'بعد',
    'قبل',
  };

  static List<String> _tokenizeArabic(String text) {
    final norm = OfflineSmartAssistantService.normalizeArabic(text);
    return norm
        .split(RegExp(r'[^\u0600-\u06FFa-z0-9]+'))
        .where((w) => w.length >= 2 && !_arabicStopWords.contains(w))
        .toList();
  }

  static String _stemArabicToken(String token) {
    if (token.length >= 4 && token.startsWith('ال')) {
      return token.substring(2);
    }
    if (token.length >= 5 &&
        (token.startsWith('و') ||
            token.startsWith('ب') ||
            token.startsWith('ل') ||
            token.startsWith('ف'))) {
      final rest = token.substring(1);
      if (rest.startsWith('ال') && rest.length >= 4) {
        return rest.substring(2);
      }
      return rest;
    }
    return token;
  }

  Future<List<AssistantInsight>> match(
    String rawQuery, {
    int maxResults = 2,
    String activeSector = 'all',
  }) async {
    final kb = await _loadKnowledgeBase();
    if (kb.topics.isEmpty) return const [];

    final correctedQuery =
        AssistantArabicNormalizer.correctTyposWithLevenshtein(rawQuery);
    final normQuery =
        OfflineSmartAssistantService.normalizeArabic(correctedQuery);
    final rawTokens = _tokenizeArabic(correctedQuery);
    if (rawTokens.isEmpty) return const [];

    final queryTokens = <String>{};
    final queryGroupIds = <int>{};
    for (final t in rawTokens) {
      queryTokens.add(t);
      final stemmed = _stemArabicToken(t);
      queryTokens.add(stemmed);
      final gid = kb.groupIndexFor(t) ?? kb.groupIndexFor(stemmed);
      if (gid != null) queryGroupIds.add(gid);
    }

    final scored = <_ScoredKnowledgeTopic>[];
    for (final topic in kb.topics) {
      double score = 0;

      for (final sq in topic.sampleQuestions) {
        final normSq = OfflineSmartAssistantService.normalizeArabic(sq);
        if (normSq == normQuery) {
          score += 20;
        } else if (normSq.contains(normQuery) || normQuery.contains(normSq)) {
          score += 10;
        }
        for (final t in _tokenizeArabic(sq)) {
          final st = _stemArabicToken(t);
          if (queryTokens.contains(t) || queryTokens.contains(st)) {
            score += 4.5;
          } else {
            final gid = kb.groupIndexFor(t) ?? kb.groupIndexFor(st);
            if (gid != null && queryGroupIds.contains(gid)) {
              score += 3.5;
            }
          }
        }
      }

      for (final kw in topic.keywords) {
        final normKw = OfflineSmartAssistantService.normalizeArabic(kw);
        if (normQuery.contains(normKw)) {
          score += 6;
        }
        for (final t in _tokenizeArabic(kw)) {
          final st = _stemArabicToken(t);
          if (queryTokens.contains(t) || queryTokens.contains(st)) {
            score += 4.0;
          } else {
            final gid = kb.groupIndexFor(t) ?? kb.groupIndexFor(st);
            if (gid != null && queryGroupIds.contains(gid)) {
              score += 3.0;
            }
          }
        }
      }

      for (final t in _tokenizeArabic('${topic.title} ${topic.summary}')) {
        final st = _stemArabicToken(t);
        if (queryTokens.contains(t) || queryTokens.contains(st)) {
          score += 2.0;
        } else {
          final gid = kb.groupIndexFor(t) ?? kb.groupIndexFor(st);
          if (gid != null && queryGroupIds.contains(gid)) {
            score += 1.5;
          } else if (st.length >= 4) {
            final prefix = st.substring(0, 3);
            if (queryTokens.any((qt) => qt.length >= 4 && qt.startsWith(prefix))) {
              score += 1.0;
            }
          }
        }
      }

      if (score > 0 && activeSector != 'all') {
        if (topic.sector == activeSector) {
          score += 5.0;
        } else if (topic.sector != 'all' && topic.sector != activeSector) {
          score -= 1.5;
        }
      }

      if (score >= 6.0) {
        scored.add(_ScoredKnowledgeTopic(topic, score));
      }
    }

    if (scored.isEmpty) return const [];
    scored.sort((a, b) => b.score.compareTo(a.score));

    return scored
        .take(maxResults)
        .map(
          (entry) => AssistantInsight(
            id: 'kb_${entry.topic.id}',
            title: '${entry.topic.category}: ${entry.topic.title}',
            summary: entry.topic.summary,
            details: entry.topic.details,
            followUpPrompts: entry.topic.followUpPrompts,
          ),
        )
        .toList();
  }
}

class _AssistantKnowledgeTopic {
  final String id;
  final String sector;
  final String category;
  final String title;
  final List<String> keywords;
  final List<String> sampleQuestions;
  final String summary;
  final List<String> details;
  final List<String> followUpPrompts;

  const _AssistantKnowledgeTopic({
    required this.id,
    this.sector = 'all',
    required this.category,
    required this.title,
    required this.keywords,
    required this.sampleQuestions,
    required this.summary,
    required this.details,
    required this.followUpPrompts,
  });

  factory _AssistantKnowledgeTopic.fromJson(Map<String, dynamic> json) {
    return _AssistantKnowledgeTopic(
      id: json['id'] as String? ?? '',
      sector: json['sector'] as String? ?? 'all',
      category: json['category'] as String? ?? 'استشارات تجارية',
      title: json['title'] as String? ?? '',
      keywords: List<String>.from(json['keywords'] as List? ?? const []),
      sampleQuestions:
          List<String>.from(json['sampleQuestions'] as List? ?? const []),
      summary: json['summary'] as String? ?? '',
      details: List<String>.from(json['details'] as List? ?? const []),
      followUpPrompts:
          List<String>.from(json['followUpPrompts'] as List? ?? const []),
    );
  }
}

class _AssistantKnowledgeBase {
  final List<Set<String>> synonymGroups;
  final List<_AssistantKnowledgeTopic> topics;

  const _AssistantKnowledgeBase({
    required this.synonymGroups,
    required this.topics,
  });

  int? groupIndexFor(String token) {
    for (int i = 0; i < synonymGroups.length; i++) {
      if (synonymGroups[i].contains(token)) return i;
    }
    return null;
  }

  factory _AssistantKnowledgeBase.fromJson(Map<String, dynamic> json) {
    final rawSyns = json['synonyms'] as List? ?? const [];
    final groups = <Set<String>>[];
    for (final g in rawSyns) {
      if (g is List) {
        final set = <String>{};
        for (final w in g) {
          final norm = OfflineSmartAssistantService.normalizeArabic(w.toString());
          if (norm.isNotEmpty) {
            set.add(norm);
            set.add(OfflineKnowledgeMatcher._stemArabicToken(norm));
          }
        }
        if (set.isNotEmpty) groups.add(set);
      }
    }
    final rawTopics = json['topics'] as List? ?? const [];
    final topics = rawTopics
        .whereType<Map<String, dynamic>>()
        .map(_AssistantKnowledgeTopic.fromJson)
        .toList();
    return _AssistantKnowledgeBase(synonymGroups: groups, topics: topics);
  }
}

class _ScoredKnowledgeTopic {
  final _AssistantKnowledgeTopic topic;
  final double score;

  const _ScoredKnowledgeTopic(this.topic, this.score);
}
