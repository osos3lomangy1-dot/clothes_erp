import 'package:clothes_erp/features/dashboard/data/services/assistant_nlu_engine.dart';

void main() {
  final context = AssistantContextMemory();

  final testCases = <(String, AssistantNluIntent)>[
    ('ازاي اتفاوض مع المورد', AssistantNluIntent.knowledge),
    (
      'اديني سكريبت كريس فوس كامل للرد على فصال الزبون كلمة بكلمة',
      AssistantNluIntent.knowledge,
    ),
    (
      'ازاي ارتب المحل من جوة بحيث الزبون يلف فيه كله ويشتري اكتر',
      AssistantNluIntent.knowledge,
    ),
    (
      'ازاي احسب القيمة العمرية للزبون Customer Lifetime Value لمحلي بالارقام',
      AssistantNluIntent.knowledge,
    ),
  ];

  for (final (text, expected) in testCases) {
    final numeric = AssistantArabicNormalizer.replaceSpokenNumbers(text);
    final norm = AssistantArabicNormalizer.normalizeBasic(numeric);
    final res = AssistantIntentScorer.score(text, context: context);
    print('TEXT: "$text"');
    print('  -> numeric: "$numeric"');
    print('  -> norm: "$norm"');
    print('  -> intent: ${res?.intent.name} (expected: ${expected.name})');
  }
}
