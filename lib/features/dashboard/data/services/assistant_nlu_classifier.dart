import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart' show rootBundle;

import '../../../../core/utils/money.dart';
import 'assistant_nlu_engine.dart';

class TrainedNluPrediction {
  const TrainedNluPrediction({
    required this.intent,
    required this.confidence,
  });

  final AssistantNluIntent intent;
  final double confidence;
}

/// Lightweight on-device Naive Bayes + Char/Word N-Gram classifier trained
/// offline on `tool/assistant_egyptian_corpus_v2.jsonl` (75k+ sentences).
class OfflineNluClassifier {
  static final _punctRe =
      RegExp(r'[؟?!\.,،:;_\-"\(\)\[\]\{\}\\/+=*&^%$#@~`><|]');
  static final _diacriticsRe = RegExp(r'[\u064B-\u065F\u0670]');
  static final _numRe = RegExp(r'\b\d+(?:\.\d+)?\b');

  static final Map<String, AssistantNluIntent> _intentByName = {
    for (final v in AssistantNluIntent.values) v.name: v,
  };

  bool _loaded = false;
  List<String> _labels = const [];
  Map<String, double> _priors = const {};
  Map<String, double> _baselines = const {};
  Map<String, Map<String, double>> _weights = const {};

  bool get isLoaded => _loaded && _labels.isNotEmpty;
  int get labelCount => _labels.length;

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final raw = await rootBundle.loadString('assets/assistant_nlu_model.json');
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      _labels = (decoded['labels'] as List<dynamic>).cast<String>();
      final rawPriors = decoded['priors'] as Map<String, dynamic>;
      _priors = {
        for (final e in rawPriors.entries)
          e.key: (e.value as num).toDouble(),
      };
      final rawBaselines = decoded['baselines'] as Map<String, dynamic>?;
      _baselines = rawBaselines == null
          ? const {}
          : {
              for (final e in rawBaselines.entries)
                e.key: (e.value as num).toDouble(),
            };
      final rawWeights = decoded['weights'] as Map<String, dynamic>;
      _weights = {
        for (final cls in rawWeights.entries)
          cls.key: {
            for (final ft in (cls.value as Map<String, dynamic>).entries)
              ft.key: (ft.value as num).toDouble(),
          },
      };
    } catch (_) {
      _labels = const [];
      _priors = const {};
      _weights = const {};
    }
  }

  static String _normalize(String text) {
    var s = Money.normalizeDigits(text).toLowerCase().trim();
    s = s.replaceAll('ـ', '');
    s = s.replaceAll(_diacriticsRe, '');
    s = s
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ى', 'ي')
        .replaceAll('ة', 'ه');
    s = s.replaceAll(_punctRe, ' ');
    s = s.replaceAll(_numRe, ' <NUM> ');
    return s.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static List<String> _extractFeatures(String norm) {
    if (norm.isEmpty) return const [];
    final words = norm.split(' ');
    final feats = <String>[];
    for (final w in words) {
      feats.add('w:$w');
    }
    for (var i = 0; i < words.length - 1; i++) {
      feats.add('b:${words[i]}_${words[i + 1]}');
    }
    for (final w in words) {
      if (w == '<NUM>' || w.length < 3) continue;
      final padded = '^$w\$';
      for (final n in const [3, 4]) {
        if (padded.length >= n) {
          for (var j = 0; j <= padded.length - n; j++) {
            feats.add('c:${padded.substring(j, j + n)}');
          }
        }
      }
    }
    return feats;
  }

  /// Classifies [rawQuery] using the trained model when confidence >= [minConfidence].
  Future<TrainedNluPrediction?> classify(
    String rawQuery, {
    double minConfidence = 0.55,
  }) async {
    await ensureLoaded();
    if (!isLoaded) return null;

    final norm = _normalize(rawQuery);
    final feats = _extractFeatures(norm);
    if (feats.isEmpty) return null;

    final scores = <String, double>{};
    final wordHits = <String, int>{};
    var maxScore = double.negativeInfinity;
    for (final lbl in _labels) {
      final wMap = _weights[lbl];
      final base = _baselines[lbl] ?? 0.0;
      var s = (_priors[lbl] ?? 0.0) + (feats.length * base);
      var wHits = 0;
      if (wMap != null) {
        for (final ft in feats) {
          final delta = wMap[ft];
          if (delta != null) {
            s += delta;
            if (ft.startsWith('w:') || ft.startsWith('b:')) {
              wHits++;
            }
          }
        }
      }
      scores[lbl] = s;
      wordHits[lbl] = wHits;
      if (s > maxScore) maxScore = s;
    }

    // Softmax over log-scores for calibrated confidence
    var sumExp = 0.0;
    String bestLbl = _labels.first;
    var bestScore = double.negativeInfinity;
    for (final e in scores.entries) {
      sumExp += math.exp((e.value - maxScore).clamp(-50.0, 0.0));
      if (e.value > bestScore) {
        bestScore = e.value;
        bestLbl = e.key;
      }
    }
    final confidence = sumExp > 0 ? 1.0 / sumExp : 0.0;
    if (confidence < minConfidence || (wordHits[bestLbl] ?? 0) < 2) {
      return null;
    }

    final mappedIntent = _intentByName[bestLbl];
    if (mappedIntent == null) return null;

    return TrainedNluPrediction(intent: mappedIntent, confidence: confidence);
  }
}

