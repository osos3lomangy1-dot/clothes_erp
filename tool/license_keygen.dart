import 'dart:io';
import 'package:clothes_erp/core/services/license_crypto_codec.dart';

void main(List<String> args) {
  stdout.writeln('================================================================');
  stdout.writeln(' مولد مفاتيح وتراخيص نظام بيعة للمطور (BAY3AH ERP LICENSE KEYGEN) ');
  stdout.writeln('================================================================\n');

  String machineId = '';
  String type = 'lifetime';
  String tier = 'enterprise';
  int days = 365;

  // 1. Check CLI arguments
  for (final arg in args) {
    if (arg.startsWith('--mid=')) {
      machineId = arg.substring(6).trim();
    } else if (arg.startsWith('--type=')) {
      type = arg.substring(7).trim();
    } else if (arg.startsWith('--tier=')) {
      tier = arg.substring(7).trim();
    } else if (arg.startsWith('--days=')) {
      days = int.tryParse(arg.substring(7).trim()) ?? 365;
    }
  }

  // 2. Interactive Input if missing
  if (machineId.isEmpty) {
    stdout.write('1. أدخل معرّف الجهاز (Machine ID) المأخوذ من العميل: ');
    final input = stdin.readLineSync()?.trim();
    if (input == null || input.isEmpty) {
      stderr.writeln('خطأ: معرّف الجهاز مطلوب.');
      exit(1);
    }
    machineId = input;
  }

  if (args.isEmpty) {
    stdout.writeln('\n2. اختر نوع الترخيص:');
    stdout.writeln('   1: ترخيص دائم مدى الحياة (Lifetime) [افتراضي]');
    stdout.writeln('   2: ترخيص اشتراك سنوي (Annual - 365 يوم)');
    stdout.writeln('   3: تمديد فترة تجريبية (Trial Extension)');
    stdout.write('   اختيارك [1-3]: ');
    final typeChoice = stdin.readLineSync()?.trim();
    if (typeChoice == '2') {
      type = 'annual';
      days = 365;
    } else if (typeChoice == '3') {
      type = 'trial_extension';
      stdout.write('   أدخل عدد أيام التمديد (مثال: 30): ');
      final daysInput = stdin.readLineSync()?.trim();
      days = int.tryParse(daysInput ?? '30') ?? 30;
    } else {
      type = 'lifetime';
    }

    stdout.writeln('\n3. اختر باقة الميزات:');
    stdout.writeln('   1: باقة Enterprise الشاملة (كافة الأنشطة والمزايا) [افتراضي]');
    stdout.writeln('   2: باقة Pro الاحترافية');
    stdout.writeln('   3: باقة Basic الأساسية');
    stdout.write('   اختيارك [1-3]: ');
    final tierChoice = stdin.readLineSync()?.trim();
    if (tierChoice == '2') {
      tier = 'pro';
    } else if (tierChoice == '3') {
      tier = 'basic';
    } else {
      tier = 'enterprise';
    }
  }

  // Normalize Machine ID format
  machineId = machineId.trim().toUpperCase();

  DateTime? expiryDate;
  if (type == 'annual' || type == 'trial_extension') {
    expiryDate = DateTime.now().add(Duration(days: days));
  }

  // Generate Cryptographic Key
  final key = LicenseCryptoCodec.generateKey(
    machineId: machineId,
    type: type,
    tier: tier,
    expiryDate: expiryDate,
  );

  final expiryLabel = expiryDate != null
      ? '${expiryDate.year}-${expiryDate.month.toString().padLeft(2, '0')}-${expiryDate.day.toString().padLeft(2, '0')} ($days يوم)'
      : 'غير منتهي الصلاحية (ترخيص دائم مدى الحياة)';

  stdout.writeln('\n================================================================');
  stdout.writeln(' تفاصيل الترخيص المُنشأ:');
  stdout.writeln(' - معرّف الجهاز: $machineId');
  stdout.writeln(' - نوع الترخيص:  ${_typeDisplay(type)}');
  stdout.writeln(' - باقة النظام:  ${tier.toUpperCase()}');
  stdout.writeln(' - الصلاحية:     $expiryLabel');
  stdout.writeln('----------------------------------------------------------------');
  stdout.writeln(' كود التفعيل المعتمد (License Key):');
  stdout.writeln('\n$key\n');
  stdout.writeln('================================================================');
  stdout.writeln('تعليمات: انسخ كود التفعيل أعلاه وأرسله للعميل لتفعيله داخل');
  stdout.writeln('إعدادات النظام -> ترخيص وتفعيل النظام.');
  stdout.writeln('================================================================\n');
}

String _typeDisplay(String type) {
  switch (type.toLowerCase()) {
    case 'lifetime':
      return 'دائم مدى الحياة (Lifetime)';
    case 'annual':
      return 'اشتراك سنوي (Annual)';
    case 'trial_extension':
      return 'تمديد فترة تجريبية (Trial Extension)';
    default:
      return type;
  }
}
