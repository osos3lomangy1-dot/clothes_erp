# 06 — دليل المطور والتشغيل الهندسي (Developer Handbook)

---

## 1. متطلبات بيئة التطوير (Prerequisites & Setup)

1. **Flutter SDK:** إصدار Flutter 3.24+ (مع تفعيل Windows Desktop).
2. **Visual Studio:** Visual Studio 2022 مع حزمة تطوير C++ لسطح المكتب (`Desktop development with C++`).
3. **Dart SDK:** مدمج مع حزمة Flutter.
4. **Git:** لإدارة النسخ وتتبع التغييرات.

### التحقق من جاهزية البيئة
```bash
flutter doctor -v
flutter config --enable-windows-desktop
```

---

## 2. تشغيل التطبيق محلياً (Run Locally)

```bash
# تشغيل التطبيق مباشرة على نظام ويندوز في وضع التطوير
flutter run -d windows
```

---

## 3. إعادة توليد الأكواد التلقائية (Code Generation)

عند إضافة أو تعديل جداول Drift، خدمات GetIt، أو كائنات Injectable، يجب تشغيل:

```bash
dart run build_runner build --delete-conflicting-outputs
```

---

## 4. تشغيل الاختبارات الآلية والتحليل (Testing & Linting)

```bash
# فحص سلامة وتناسق الكود
flutter analyze

# تشغيل الاختبارات السريعة
flutter test

# تشغيل الاختبارات بمخرجات تفصيلية موسعة
flutter test --reporter expanded

# تشغيل ملف اختبار محدد (مثال: اختبارات الترقية الحقيقية)
flutter test test/real_v1_to_v11_migration_test.dart
```

---

## 5. بناء النسخة الإنتاجية للمستخدم النهائي (Windows Release Build)

```bash
flutter build windows --release
```

- **موقع الإخراج المترجم:**
  `build\windows\x64\runner\Release\`
- **الملف التنفيذي الناتج:**
  `bay3ah.exe`
- **الحزم والملفات التابعة الضرورية للتشغيل:**
  - `bay3ah.exe`
  - `flutter_windows.dll`
  - `sqlite3.dll`
  - مجلد `data/` (الأصول والخطوط)

---

## 6. مسارات ملفات النظام وقواعد البيانات على Windows

| نوع الملف | المسار الفعلي على جهاز المستخدم |
|---|---|
| **قاعدة البيانات النشطة** | `%APPDATA%\Roaming\com.orkeed.clothes_erp\clothes_erp.sqlite` |
| **سجلات التدوين المسبق (WAL)** | `%APPDATA%\Roaming\com.orkeed.clothes_erp\clothes_erp.sqlite-wal` |
| **مؤشر الترقية النشط** | `%APPDATA%\Roaming\com.orkeed.clothes_erp\migration.inprogress` |
| **النسخ الاحتياطية المعتمدة** | `%APPDATA%\Roaming\com.orkeed.clothes_erp\backups\pre_migration_*.sqlite` |
| **سجلات الأعطال المحلية** | `%APPDATA%\Roaming\com.orkeed.clothes_erp\crash_logs\` |

---

## 7. هيكل المستودع البرمجي (Repository Architecture)

```text
clothes_erp/
├── lib/
│   ├── core/                  # النواة المشتركة
│   │   ├── constants/         # ألوان، قطاعات، ثوابت
│   │   ├── database/          # Drift Database, Migrations, Markers, Backups, Recovery
│   │   ├── di/                # حقن التبعيات (GetIt & Injectable)
│   │   ├── features/          # بوابة الميزات FeatureGate
│   │   ├── presentation/      # شاشات النواة المشتركة (شاشة الطوارئ)
│   │   ├── services/          # النسخ السحابي، السجلات، وتصدير إكسيل
│   │   ├── theme/             # الثيم والهوية البصرية Cairo
│   │   └── utils/             # معالجة النصوص العربية والحسابات
│   ├── features/              # الميزات والوحدات الوظيفية
│   │   ├── auth/              # تسجيل الدخول والأدوار
│   │   ├── catalog/           # المنتجات، المتغيرات، والتصنيفات
│   │   ├── customers/         # العملاء وحساباتهم
│   │   ├── dashboard/         # لوحة التحكم التنفيذية
│   │   ├── employees/         # الموظفون والرواتب والسلف
│   │   ├── expenses/          # المصروفات والخزينة
│   │   ├── installments/      # الأقساط والسداد المجمع
│   │   ├── inventory/         # المخزون وحركات الجرد
│   │   ├── pos/               # نقطة البيع السريعة والفواتير
│   │   ├── promotions/        # محرك العروض والخصومات
│   │   ├── purchases/         # المشتريات والموردين
│   │   ├── settings/          # إعدادات النظام والهوية
│   │   └── shifts/            # الورديات ومطابقة النقدية
│   └── main.dart              # نقطة البداية وفحص الطوارئ
├── test/                      # 581 اختباراً آلياً شاملاً
├── windows/                   # إعدادات C++ و CMake ومخرجات bay3ah.exe
└── docs/                      # التوثيق الهندسي الشامل
```
