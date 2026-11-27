import 'dart:convert';
import 'dart:io';

import 'package:clothes_erp/features/dashboard/data/services/assistant_nlu_engine.dart';

void main() async {
  final file = File('tool/egyptian_numbers_v2.jsonl');
  if (!file.existsSync()) {
    print('File not found: ${file.path}');
    return;
  }

  final lines = await file.readAsLines();
  int total = 0;
  int passed = 0;
  final missedByFormat = <String, int>{};
  final totalByFormat = <String, int>{};
  final sampleMisses = <String>[];

  final sw = Stopwatch()..start();
  for (final line in lines) {
    if (line.trim().isEmpty) continue;
    final row = jsonDecode(line) as Map<String, dynamic>;
    final text = row['text'] as String;
    final expected = (row['value'] as num?)?.toDouble();
    final format = (row['format'] as String?) ?? 'unknown';

    total++;
    totalByFormat[format] = (totalByFormat[format] ?? 0) + 1;

    final replaced = AssistantArabicNormalizer.replaceSpokenNumbers(text);
    final match = RegExp(r'\d+(?:\.\d+)?').firstMatch(replaced);
    final parsed = match != null ? double.tryParse(match.group(0)!) : null;

    final ok = expected == null
        ? parsed == null
        : (parsed != null && (parsed - expected).abs() < 0.001);
    if (ok) {
      passed++;
    } else {
      missedByFormat[format] = (missedByFormat[format] ?? 0) + 1;
      if (sampleMisses.length < 40) {
        sampleMisses.add(
          '[$format] "$text" => "$replaced" (got=$parsed, exp=$expected)',
        );
      }
    }
  }
  sw.stop();

  final pct = (passed * 100 / total).toStringAsFixed(2);
  print(
    'Numbers Benchmark: $passed / $total ($pct%) in ${sw.elapsedMilliseconds}ms',
  );
  print('By format:');
  for (final e in totalByFormat.entries) {
    final miss = missedByFormat[e.key] ?? 0;
    final ok = e.value - miss;
    final fpct = (ok * 100 / e.value).toStringAsFixed(2);
    print('  ${e.key}: $ok / ${e.value} ($fpct%)');
  }
  print('\nSample misses:');
  for (final m in sampleMisses) {
    print('  $m');
  }
}
