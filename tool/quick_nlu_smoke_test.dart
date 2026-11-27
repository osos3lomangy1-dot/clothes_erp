import 'package:clothes_erp/features/dashboard/data/services/assistant_nlu_engine.dart';

void main() {
  print('Testing AssistantIntentScorer fast unit tests...');
  final context = AssistantContextMemory();

  final testCases = <(String, AssistantNluIntent)>[
    ('سجل صنف قميص بـ 250 تكلفة 150', AssistantNluIntent.addProduct),
    (
      'اشتريت 10 بنطلون من الحاج احمد بـ 3000',
      AssistantNluIntent.recordPurchase,
    ),
    ('صرفت 500 جنيه كهرباء', AssistantNluIntent.recordExpense),
    ('سددت الحاج رمضان 20000', AssistantNluIntent.paySupplier),
    ('حصلت من عميل 500 جنيه قسط', AssistantNluIntent.collectInstallment),
    ('احسب الزكاة بسعر الذهب 3200', AssistantNluIntent.calculateZakat),
    ('كسبت كام النهاردة', AssistantNluIntent.todayProfit),
    ('ايه هو نقطة التعادل', AssistantNluIntent.knowledge),
    ('نصاب الزكاة كام النهاردة', AssistantNluIntent.knowledge),
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

  int passed = 0;
  for (final (text, expected) in testCases) {
    final res = AssistantIntentScorer.score(text, context: context);
    if (res?.intent == expected) {
      passed++;
      print('  PASS: "$text" => ${res?.intent.name}');
    } else {
      print(
        '  FAIL: "$text" => got=${res?.intent.name}, expected=${expected.name}',
      );
    }
  }

  print('\nSummary: $passed / ${testCases.length} passed perfectly!');
}
