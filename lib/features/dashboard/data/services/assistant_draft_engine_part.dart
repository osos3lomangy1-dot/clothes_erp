part of 'offline_smart_assistant_service.dart';

extension AssistantDraftEnginePart on OfflineSmartAssistantService {
  /// Interactive How-To Guide (11 topics) for Arabic & Egyptian colloquial queries.
  AssistantInsight? matchHowToGuide(String rawQuery) {
    final q = OfflineSmartAssistantService.normalizeArabic(rawQuery);
    final isQuestion = q.contains('ازاي') ||
        q.contains('كيف') ||
        q.contains('طريقه') ||
        q.contains('اعمل') ||
        q.contains('اغير') ||
        q.contains('اضيف') ||
        q.contains('فين') ||
        q.contains('خطوات');
    if (!isQuestion) return null;

    if (q.contains('اسم المحل') ||
        q.contains('اسم المتجر') ||
        q.contains('الفاتوره') ||
        q.contains('الايصال') ||
        q.contains('الشعار')) {
      return const AssistantInsight(
        id: 'howto_receipt',
        title: 'دليل: تغيير اسم المحل وتخصيص الفاتورة',
        summary: 'يمكنك تعديل اسم المحل وبيانات الإيصال خلال ثوانٍ:',
        details: [
          '1. افتح "تخصيص الفاتورة الحرارية" من الإعدادات أو الزر بالأسفل.',
          '2. عدّل اسم المتجر، رقم الهاتف، العنوان، والرسالة الترحيبية.',
          '3. اضغط حفظ [F12] لتطبيق التغيير فوراً على كل الفواتير.',
        ],
        actionLabel: 'فتح الشاشة الآن',
        actionRoute: AssistantActionRoute.receiptCustomizer,
      );
    }

    final isEncyclopediaQuery = q.contains('فرق') ||
        q.contains('باقه') ||
        q.contains('هديه') ||
        q.contains('تضخم') ||
        q.contains('غلاء') ||
        q.contains('استبدال') ||
        q.contains('ترتيب المحل') ||
        q.contains('عرض البضاعه') ||
        q.contains('سيوله') ||
        q.contains('50/30/20') ||
        q.contains('منافس') ||
        q.contains('محل جنبي') ||
        q.contains('نزل السعر') ||
        q.contains('غالي') ||
        q.contains('بزنس مان');

    if (!isEncyclopediaQuery &&
        (q.contains('خصم') || q.contains('منع الخصم') || q.contains('تعديل السعر'))) {
      return const AssistantInsight(
        id: 'howto_discount_guard',
        title: 'دليل: منع الخصم اليدوي أو تعديل السعر للكاشير',
        summary: 'لحماية الأسعار ومنع الخصومات غير المصرح بها:',
        details: [
          '1. افتح "إعدادات النظام" -> قسم "صلاحيات الكاشير".',
          '2. عطّل خيار "السماح بالخصم اليدوي للكاشير".',
          '3. كما يمكنك تفعيل "حماية المدير بالرقم السري" لاعتماد المرتجعات.',
        ],
        actionLabel: 'فتح الشاشة الآن',
        actionRoute: AssistantActionRoute.settings,
      );
    }

    if (q.contains('كاشير') || q.contains('موظف') || q.contains('pin')) {
      return const AssistantInsight(
        id: 'howto_employees',
        title: 'دليل: إضافة كاشير وتعيين رمز PIN',
        summary: 'خطوات إنشاء حساب كاشير للدخول السريع بالـ PIN:',
        details: [
          '1. افتح شاشة "الموظفين والصلاحيات".',
          '2. اضغط "إضافة موظف جديد" واختر الدور (كاشير أو مدير).',
          '3. أدخل رمز PIN من 4 أرقام للدخول السريع واضغط حفظ.',
        ],
        actionLabel: 'فتح الشاشة الآن',
        actionRoute: AssistantActionRoute.employees,
        requiredFeatureKey: FeatureKeys.employees,
      );
    }

    if (q.contains('نسخ') || q.contains('احتياطي') || q.contains('باك اب')) {
      return const AssistantInsight(
        id: 'howto_backup',
        title: 'دليل: النسخ الاحتياطي للبيانات',
        summary: 'لأخذ نسخة احتياطية فورية أو تفعيل النسخ التلقائي:',
        details: [
          '1. افتح "إعدادات النظام" -> قسم "النسخ الاحتياطي".',
          '2. اختر مجلد الحفظ وفعّل النسخ التلقائي اليومي وعند الإغلاق.',
          '3. أو اضغط "إنشاء نسخة احتياطية الآن" للحفظ الفوري.',
        ],
        actionLabel: 'فتح الشاشة الآن',
        actionRoute: AssistantActionRoute.settings,
      );
    }

    if (q.contains('اكسيل') || q.contains('استيراد') || q.contains('شيت')) {
      return const AssistantInsight(
        id: 'howto_excel',
        title: 'دليل: استيراد البيانات من ملف إكسيل',
        summary: 'لنقل المنتجات والعملاء والأقساط والمصروفات دفعة واحدة:',
        details: [
          '1. افتح "مركز الإكسيل واستيراد البيانات".',
          '2. اختر ملف الإكسيل (يمكنك تفعيل الاستيراد المرن للبيانات الناقصة).',
          '3. راجع المعاينة واضغط "تأكيد وحفظ البيانات".',
        ],
        actionLabel: 'فتح الشاشة الآن',
        actionRoute: AssistantActionRoute.excelMigration,
      );
    }

    if (!q.contains('عجز') &&
        !q.contains('سرقه') &&
        !q.contains('تلاعب') &&
        (q.contains('ورديه') || q.contains('تقفيل') || q.contains('الدرج'))) {
      return const AssistantInsight(
        id: 'howto_shift',
        title: 'دليل: فتح وتقفيل الوردية ومطابقة الدرج',
        summary: 'لإنهاء الوردية ومطابقة النقدية الفعلية:',
        details: [
          '1. افتح شاشة "الورديات وتصفية الدرج".',
          '2. اضغط "تقفيل الوردية" وأدخل المبلغ الفعلي المعدود في الدرج.',
          '3. راجع العجز/الزيادة واطبع تقرير Z.',
        ],
        actionLabel: 'فتح الشاشة الآن',
        actionRoute: AssistantActionRoute.shifts,
        requiredFeatureKey: FeatureKeys.shifts,
      );
    }

    if (q.contains('تقسيط') || q.contains('قسط')) {
      return const AssistantInsight(
        id: 'howto_installments',
        title: 'دليل: البيع بالتقسيط ومتابعة الأقساط',
        summary: 'لتفعيل التقسيط وتحصيل الأقساط الشهرية:',
        details: [
          '1. تأكد من تفعيل ميزة "نظام التقسيط" من إعدادات النظام.',
          '2. عند البيع في الكاشير اختر عميلاً ثم طريقة الدفع "تقسيط".',
          '3. تابع الأقساط المستحقة وسجل السداد من شاشة "التقسيط".',
        ],
        actionLabel: 'فتح الشاشة الآن',
        actionRoute: AssistantActionRoute.installments,
        requiredFeatureKey: FeatureKeys.installments,
      );
    }

    if (q.contains('تعدد') || q.contains('نشاط') || q.contains('متاجر') || q.contains('ميزات')) {
      return const AssistantInsight(
        id: 'howto_presets',
        title: 'دليل: تبديل نشاط المتجر وتعدد الأنشطة',
        summary: 'لتخصيص النظام لملابس، موبايلات، مطاعم، أو أكثر من نشاط:',
        details: [
          '1. افتح "إعدادات النظام" -> "نمط النشاط التجاري والميزات".',
          '2. اختر القالب المناسب أو فعّل/عطّل أي ميزة منفردة.',
          '3. تُعزل الشاشات غير المطلوبة تلقائياً للحفاظ على بساطة الواجهة.',
        ],
        actionLabel: 'فتح الشاشة الآن',
        actionRoute: AssistantActionRoute.settings,
      );
    }

    if (q.contains('شريك') || q.contains('شركاء') || q.contains('راس مال')) {
      return const AssistantInsight(
        id: 'howto_partners',
        title: 'دليل: إضافة شريك وتسجيل رأس المال',
        summary: 'لتسجيل حصص الشركاء ومتابعة المسحوبات والأرباح:',
        details: [
          '1. افتح شاشة "الشركاء ورأس المال".',
          '2. اضغط "إضافة شريك" وأدخل الاسم، النسبة %، ورأس المال.',
          '3. تُحسب حصة كل شريك من صافي الربح تلقائياً.',
        ],
        actionLabel: 'فتح الشاشة الآن',
        actionRoute: AssistantActionRoute.partners,
        requiredFeatureKey: FeatureKeys.partners,
      );
    }

    if (!isEncyclopediaQuery &&
        (q.contains('سعر') || q.contains('صنف') || q.contains('منتج'))) {
      return const AssistantInsight(
        id: 'howto_products',
        title: 'دليل: إضافة صنف أو تعديل السعر الرسمي',
        summary: 'لإضافة منتجات جديدة أو تحديث أسعار البيع والتكلفة:',
        details: [
          '1. افتح شاشة "المنتجات والمخزون".',
          '2. اضغط [F3] لإضافة صنف جديد أو اضغط تعديل على الصنف الحالي.',
          '3. حدّث السعر الرسمي واضغط حفظ [F12].',
        ],
        actionLabel: 'فتح الشاشة الآن',
        actionRoute: AssistantActionRoute.products,
        requiredFeatureKey: FeatureKeys.inventory,
      );
    }

    if (q.contains('مرتجع') || q.contains('ارجاع') || q.contains('استبدال')) {
      return const AssistantInsight(
        id: 'howto_returns',
        title: 'دليل: عمل مرتجع أو استبدال فاتورة',
        summary: 'لإرجاع صنف للمخزون واسترداد قيمته من الدرج:',
        details: [
          '1. افتح شاشة "مرتجعات المبيعات".',
          '2. ابحث برقم الفاتورة أو اسم العميل [F2] واختر الفاتورة.',
          '3. حدد الكمية وسبب الإرجاع ثم اضغط تنفيذ [F12].',
        ],
        actionLabel: 'فتح الشاشة الآن',
        actionRoute: AssistantActionRoute.returns,
      );
    }

    final phoneMatch = RegExp(
      r'(?:تغيير|تعديل) (?:رقم )?(?:هاتف|تليفون|موبايل)(?: المحل| المتجر| الفاتوره)?(?: الي)?\s+([+\d\s-]+)$',
    ).firstMatch(q);
    if (phoneMatch != null) {
      final rawPhone = Money.normalizeDigits(phoneMatch.group(1)!).trim();
      if (rawPhone.isNotEmpty) {
        return AssistantInsight(
          id: 'cmd_update_phone',
          title: 'تأكيد تعديل رقم هاتف الفاتورة',
          summary: 'هل تريد تغيير رقم هاتف المتجر في الفواتير إلى "$rawPhone"؟',
          details: const ['يتطلب التنفيذ صلاحية مدير (Admin).'],
          pendingCommand: AssistantPendingCommand(
            kind: AssistantCommandKind.updateStorePhone,
            title: 'تغيير رقم هاتف الفاتورة',
            description: rawPhone,
            stringValue: rawPhone,
            touchesFeatureGate: false,
          ),
        );
      }
    }

    return null;
  }

  /// Parses direct settings commands into a pending confirmation command.
  AssistantInsight? parseCommand(String rawQuery) {
    final q = OfflineSmartAssistantService.normalizeArabic(rawQuery);
    if (q.contains('ازاي') ||
        q.contains('كيف') ||
        q.contains('طريقه') ||
        q.contains('خطوات') ||
        rawQuery.trim().endsWith('؟') ||
        rawQuery.trim().endsWith('?')) {
      return null;
    }
    final enable = q.contains('فعل') ||
        q.contains('تفعيل') ||
        q.contains('شغل') ||
        q.contains('تشغيل') ||
        q.contains('اسمح') ||
        q.contains('سماح');
    final disable = q.contains('عطل') ||
        q.contains('تعطيل') ||
        q.contains('اقفل') ||
        q.contains('ايقاف') ||
        q.contains('امنع') ||
        q.contains('منع');

    if ((enable || disable) && q.contains('الجرد الاعمي')) {
      final target = enable && !disable;
      return AssistantInsight(
        id: 'cmd_blind_shift',
        title: 'تأكيد تعديل إعداد النظام',
        summary: target
            ? 'هل تريد تفعيل "الجرد الأعمى عند تقفيل الوردية"؟'
            : 'هل تريد تعطيل "الجرد الأعمى عند تقفيل الوردية"؟',
        details: const ['يتطلب التنفيذ صلاحية مدير (Admin).'],
        pendingCommand: AssistantPendingCommand(
          kind: AssistantCommandKind.toggleBlindShiftClosing,
          title: 'الجرد الأعمى عند تقفيل الوردية',
          description: target ? 'تفعيل الميزة' : 'تعطيل الميزة',
          boolValue: target,
          touchesFeatureGate: true,
        ),
      );
    }

    if ((enable || disable) &&
        (q.contains('حمايه المدير') ||
            q.contains('pin المدير') ||
            q.contains('حمايه pin') ||
            q.contains('الرقم السري للمدير'))) {
      final target = enable && !disable;
      return AssistantInsight(
        id: 'cmd_manager_pin',
        title: 'تأكيد تعديل إعداد الأمان',
        summary: target
            ? 'هل تريد تفعيل "حماية المدير بالرقم السري"؟'
            : 'هل تريد تعطيل "حماية المدير بالرقم السري"؟',
        details: const ['يتطلب التنفيذ صلاحية مدير (Admin).'],
        pendingCommand: AssistantPendingCommand(
          kind: AssistantCommandKind.toggleManagerPinProtection,
          title: 'حماية المدير بالرقم السري',
          description: target ? 'تفعيل الحماية' : 'تعطيل الحماية',
          boolValue: target,
          touchesFeatureGate: true,
        ),
      );
    }

    if ((enable || disable) &&
        (q.contains('الخصم اليدوي') || q.contains('خصم الكاشير'))) {
      final target = enable && !disable;
      return AssistantInsight(
        id: 'cmd_manual_discount',
        title: 'تأكيد تعديل صلاحيات الكاشير',
        summary: target
            ? 'هل تريد السماح للكاشير بالخصم اليدوي؟'
            : 'هل تريد منع الخصم اليدوي عن الكاشير؟',
        details: const ['يتطلب التنفيذ صلاحية مدير (Admin).'],
        pendingCommand: AssistantPendingCommand(
          kind: AssistantCommandKind.toggleAllowManualDiscount,
          title: 'الخصم اليدوي للكاشير',
          description: target ? 'السماح بالخصم اليدوي' : 'منع الخصم اليدوي',
          boolValue: target,
          touchesFeatureGate: false,
        ),
      );
    }

    if ((enable || disable) &&
        (q.contains('النسخ الاحتياطي التلقائي') ||
            q.contains('النسخ التلقائي'))) {
      final target = enable && !disable;
      return AssistantInsight(
        id: 'cmd_auto_backup',
        title: 'تأكيد تعديل النسخ الاحتياطي',
        summary: target
            ? 'هل تريد تفعيل النسخ الاحتياطي التلقائي؟'
            : 'هل تريد إيقاف النسخ الاحتياطي التلقائي؟',
        details: const ['يتطلب التنفيذ صلاحية مدير (Admin).'],
        pendingCommand: AssistantPendingCommand(
          kind: AssistantCommandKind.toggleAutoBackup,
          title: 'النسخ الاحتياطي التلقائي',
          description: target ? 'تفعيل' : 'تعطيل',
          boolValue: target,
          touchesFeatureGate: false,
        ),
      );
    }

    if ((q.contains('اعمل نسخه احتياطيه') ||
            q.contains('نسخه احتياطيه فوريه') ||
            q.contains('خد باك اب') ||
            q.contains('باك اب دلوقتي')) &&
        !q.contains('تلقائي')) {
      return const AssistantInsight(
        id: 'cmd_run_backup_now',
        title: 'تأكيد إنشاء نسخة احتياطية فورية',
        summary: 'هل تريد إنشاء نسخة احتياطية كاملة لقاعدة البيانات الآن؟',
        details: ['يتطلب التنفيذ صلاحية مدير (Admin).'],
        pendingCommand: AssistantPendingCommand(
          kind: AssistantCommandKind.runBackupNow,
          title: 'نسخة احتياطية فورية',
          description: 'إنشاء نسخة احتياطية الآن',
          touchesFeatureGate: false,
        ),
      );
    }

    final renameMatch = RegExp(
      r'(?:تغيير اسم (?:المحل|المتجر)(?: الي)?|سمي المحل)\s+(.+)$',
    ).firstMatch(q);
    if (renameMatch != null) {
      final rawName = rawQuery
          .replaceFirst(
            RegExp(
              r'^(?:تغيير اسم (?:المحل|المتجر)(?:\s+(?:إلى|الى|الي))?|سمي المحل)\s+',
            ),
            '',
          )
          .trim();
      if (rawName.isNotEmpty) {
        return AssistantInsight(
          id: 'cmd_rename_store',
          title: 'تأكيد تغيير اسم المتجر',
          summary: 'هل تريد تغيير اسم المتجر في الفواتير إلى "$rawName"؟',
          details: const ['يتطلب التنفيذ صلاحية مدير (Admin).'],
          pendingCommand: AssistantPendingCommand(
            kind: AssistantCommandKind.updateStoreName,
            title: 'تغيير اسم المتجر',
            description: rawName,
            stringValue: rawName,
            touchesFeatureGate: false,
          ),
        );
      }
    }

    final phoneMatch = RegExp(
      r'(?:تغيير|تعديل) (?:رقم )?(?:هاتف|تليفون|موبايل)(?: المحل| المتجر| الفاتوره)?(?: الي)?\s+([+\d\s-]+)$',
    ).firstMatch(q);
    if (phoneMatch != null) {
      final rawPhone = Money.normalizeDigits(phoneMatch.group(1)!).trim();
      if (rawPhone.isNotEmpty) {
        return AssistantInsight(
          id: 'cmd_update_phone',
          title: 'تأكيد تعديل رقم هاتف الفاتورة',
          summary: 'هل تريد تغيير رقم هاتف المتجر في الفواتير إلى "$rawPhone"؟',
          details: const ['يتطلب التنفيذ صلاحية مدير (Admin).'],
          pendingCommand: AssistantPendingCommand(
            kind: AssistantCommandKind.updateStorePhone,
            title: 'تغيير رقم هاتف الفاتورة',
            description: rawPhone,
            stringValue: rawPhone,
            touchesFeatureGate: false,
          ),
        );
      }
    }

    return null;
  }

  /// Executes an approved [AssistantPendingCommand] strictly for `admin` role.
  Future<String> executeCommand(
    AssistantPendingCommand cmd, {
    required String userId,
    required String userRole,
    required FeatureGate gate,
  }) async {
    final isAdmin = userRole.toLowerCase() == 'admin';
    if (!isAdmin) {
      if (cmd.kind == AssistantCommandKind.addCustomer) {
        final custEnabled = await gate.isEnabled(FeatureKeys.customers);
        if (!custEnabled || !CashierPermissionsService.current.allowManageCustomers) {
          throw Exception('غير مصرح: إضافة العملاء متاحة للمدير أو الكاشير المصرح له فقط');
        }
      } else if (cmd.kind == AssistantCommandKind.collectInstallment) {
        final instEnabled = await gate.isEnabled(FeatureKeys.installments);
        if (!instEnabled) {
          throw Exception('غير مصرح: تحصيل الأقساط غير مفعل أو متاح للمدير فقط');
        }
      } else {
        throw Exception('غير مصرح: تنفيذ تعديلات الإعدادات متاح لحساب المدير (admin) فقط');
      }
    }

    switch (cmd.kind) {
      case AssistantCommandKind.toggleBlindShiftClosing:
        await gate.setFeatureEnabled(
          FeatureKeys.blindShiftClosing,
          cmd.boolValue ?? true,
          userId: userId,
        );
        return 'تم ${cmd.boolValue == true ? 'تفعيل' : 'تعطيل'} الجرد الأعمى بنجاح.';
      case AssistantCommandKind.toggleManagerPinProtection:
        await gate.setFeatureEnabled(
          FeatureKeys.managerPinProtection,
          cmd.boolValue ?? true,
          userId: userId,
        );
        return 'تم ${cmd.boolValue == true ? 'تفعيل' : 'تعطيل'} حماية المدير بالرقم السري بنجاح.';
      case AssistantCommandKind.toggleAllowManualDiscount:
        final updated = CashierPermissionsService.current.copyWith(
          allowManualDiscount: cmd.boolValue ?? false,
        );
        await CashierPermissionsService.save(gate, updated, userId: userId);
        return 'تم ${cmd.boolValue == true ? 'السماح بالخصم اليدوي للكاشير' : 'منع الخصم اليدوي عن الكاشير'} بنجاح.';
      case AssistantCommandKind.toggleAutoBackup:
        await gate.setMeta(
          BackupMetaKeys.autoEnabled,
          (cmd.boolValue ?? true) ? '1' : '0',
          userId: userId,
        );
        return 'تم ${cmd.boolValue == true ? 'تفعيل' : 'تعطيل'} النسخ الاحتياطي التلقائي بنجاح.';
      case AssistantCommandKind.updateStoreName:
        final newName = (cmd.stringValue ?? '').trim();
        if (newName.isEmpty) {
          throw Exception('اسم المتجر لا يمكن أن يكون فارغاً');
        }
        final updated = ReceiptSettingsService.current.copyWith(
          storeName: newName,
        );
        await ReceiptSettingsService.save(updated, gate, userId: userId);
        return 'تم تحديث اسم المتجر إلى "$newName" بنجاح.';
      case AssistantCommandKind.updateStorePhone:
        final newPhone = (cmd.stringValue ?? '').trim();
        if (newPhone.isEmpty) {
          throw Exception('رقم الهاتف لا يمكن أن يكون فارغاً');
        }
        final updated = ReceiptSettingsService.current.copyWith(
          storePhone: newPhone,
        );
        await ReceiptSettingsService.save(updated, gate, userId: userId);
        return 'تم تحديث رقم هاتف الفاتورة إلى "$newPhone" بنجاح.';
      case AssistantCommandKind.recordPurchase:
        return _execRecordPurchase(cmd.payload, userId: userId);
      case AssistantCommandKind.addProduct:
        return _execAddProduct(cmd.payload, userId: userId);
      case AssistantCommandKind.updateProductPriceOrStock:
        return _execUpdateProductPriceOrStock(cmd.payload, userId: userId);
      case AssistantCommandKind.recordExpense:
        return _execRecordExpense(cmd.payload, userId: userId);
      case AssistantCommandKind.paySupplier:
        return _execPaySupplier(cmd.payload, userId: userId);
      case AssistantCommandKind.addCustomer:
        return _execAddCustomer(cmd.payload, userId: userId);
      case AssistantCommandKind.collectInstallment:
        return _execCollectInstallment(cmd.payload, userId: userId);
      case AssistantCommandKind.calculateZakat:
        return 'تم حساب زكاة المال وعروض التجارة بنجاح.';
      case AssistantCommandKind.runBackupNow:
        final backupResult = await LocalBackupService(_db, gate).createBackup(
          userId: userId,
        );
        return 'تم إنشاء النسخة الاحتياطية بنجاح: ${backupResult.filePath}';
    }
  }

  Future<String> _execAddCustomer(
    Map<String, dynamic> payload, {
    required String userId,
  }) async {
    final name = (payload['customerName'] as String? ?? '').trim();
    final phone = Money.normalizeDigits(payload['phone'] as String? ?? '').trim();
    if (name.isEmpty || phone.isEmpty) {
      throw Exception('اسم العميل ورقم الهاتف مطلوبان');
    }
    final now = DateTime.now();
    return _db.transaction(() async {
      final branchId = await _resolveBranchId();
      final custId = _genId('cust');
      await _db.into(_db.customers).insert(
            CustomersCompanion.insert(
              id: custId,
              branchId: branchId,
              name: name,
              phone: phone,
              createdAt: now,
              updatedAt: now,
            ),
          );
      await _insertAudit(
        branchId: branchId,
        userId: userId,
        action: 'assistant_add_customer',
        entity: 'customer',
        entityId: custId,
        newValue: '$name ($phone)',
        now: now,
      );
      lastUndoToken = AssistantUndoToken(
        kind: AssistantCommandKind.addCustomer,
        recordId: custId,
        label: 'إضافة عميل: $name',
      );
      return 'تمت إضافة العميل "$name" ($phone) بنجاح.';
    });
  }

  Future<String> _execCollectInstallment(
    Map<String, dynamic> payload, {
    required String userId,
  }) async {
    final customerName = (payload['customerName'] as String? ?? '').trim();
    final amountEgp = (payload['amountEgp'] as num?)?.toDouble() ?? 0;
    if (customerName.isEmpty || amountEgp <= 0) {
      throw Exception('بيانات تحصيل القسط غير مكتملة');
    }
    final amountPiasters = (amountEgp * 100).round();
    final now = DateTime.now();

    return _db.transaction(() async {
      final branchId = await _resolveBranchId();
      final customers = await (_db.select(_db.customers)
            ..where((c) => c.deletedAt.isNull()))
          .get();
      final norm = OfflineSmartAssistantService.normalizeArabic(customerName);
      Customer? targetCust;
      for (final c in customers) {
        if (OfflineSmartAssistantService.normalizeArabic(c.name) == norm ||
            OfflineSmartAssistantService.normalizeArabic(c.name).contains(norm)) {
          targetCust = c;
          break;
        }
      }
      if (targetCust == null) {
        throw Exception('لم يتم العثور على عميل باسم "$customerName"');
      }

      final plans = await (_db.select(_db.customerInstallments)
            ..where((i) =>
                i.customerId.equals(targetCust!.id) &
                i.deletedAt.isNull() &
                (i.status.equals('overdue') | i.status.equals('active'))))
          .get();
      if (plans.isEmpty) {
        throw Exception('لا توجد عقود تقسيط نشطة أو متأخرة للعميل "${targetCust.name}"');
      }

      plans.sort((a, b) {
        if (a.status == 'overdue' && b.status != 'overdue') return -1;
        if (b.status == 'overdue' && a.status != 'overdue') return 1;
        return a.endDate.compareTo(b.endDate);
      });
      final plan = plans.first;
      final newRemaining = (plan.remainingPiasters - amountPiasters)
          .clamp(0, plan.totalPiasters);
      final newStatus = newRemaining == 0 ? 'completed' : 'active';
      final payId = _genId('ipay');

      await _db.into(_db.installmentPayments).insert(
            InstallmentPaymentsCompanion.insert(
              id: payId,
              branchId: branchId,
              customerInstallmentId: plan.id,
              amountPiasters: amountPiasters,
              paymentMethod: 'cash',
              paidAt: now,
              notes: const Value('تحصيل قسط عبر المساعد الذكي'),
              recordedBy: userId,
              createdAt: now,
              updatedAt: now,
            ),
          );
      await (_db.update(_db.customerInstallments)
            ..where((i) => i.id.equals(plan.id)))
          .write(
        CustomerInstallmentsCompanion(
          remainingPiasters: Value(newRemaining),
          status: Value(newStatus),
          updatedAt: Value(now),
        ),
      );
      await _insertAudit(
        branchId: branchId,
        userId: userId,
        action: 'assistant_collect_installment',
        entity: 'customer_installment',
        entityId: plan.id,
        oldValue: Money(plan.remainingPiasters).toDisplay(),
        newValue: Money(newRemaining).toDisplay(),
        now: now,
      );
      return 'تم تحصيل قسط ${Money(amountPiasters).toDisplay()} ج.م من "${targetCust.name}"؛ المتبقي: ${Money(newRemaining).toDisplay()} ج.م.';
    });
  }

  Future<String> _resolveBranchId() async {
    final row = await (_db.select(_db.appMeta)
          ..where((m) => m.key.equals('branch.active_id')))
        .getSingleOrNull();
    final val = row?.value.trim() ?? '';
    return val.isNotEmpty ? val : 'branch_main';
  }

  String _genId(String prefix) {
    final us = DateTime.now().microsecondsSinceEpoch;
    return '${prefix}_$us';
  }

  Future<String> _ensureDefaultCategoryId(String branchId, DateTime now) async {
    final existing = await (_db.select(_db.categories)
          ..where((c) => c.deletedAt.isNull()))
        .get();
    if (existing.isNotEmpty) return existing.first.id;
    final catId = _genId('cat');
    await _db.into(_db.categories).insert(
          CategoriesCompanion.insert(
            id: catId,
            branchId: branchId,
            name: 'عام',
            createdAt: now,
            updatedAt: now,
          ),
        );
    return catId;
  }

  Future<void> _insertAudit({
    required String branchId,
    required String userId,
    required String action,
    required String entity,
    required String entityId,
    String? oldValue,
    String? newValue,
    required DateTime now,
  }) async {
    await _db.into(_db.auditLogs).insert(
          AuditLogsCompanion.insert(
            id: _genId('aud'),
            branchId: branchId,
            userId: userId,
            action: action,
            entity: entity,
            entityId: entityId,
            oldValue: Value(oldValue),
            newValue: Value(newValue),
            createdAt: now,
          ),
        );
  }

  Future<String> _execRecordPurchase(
    Map<String, dynamic> payload, {
    required String userId,
  }) async {
    final productName = (payload['productName'] as String? ?? '').trim();
    final supplierName = (payload['supplierName'] as String? ?? '').trim();
    final costEgp = (payload['costEgp'] as num?)?.toDouble() ?? 0;
    final qty = (payload['qty'] as num?)?.toInt() ?? 0;
    final isCredit = payload['paymentType'] == 'credit';

    if (productName.isEmpty || supplierName.isEmpty || costEgp <= 0 || qty <= 0) {
      throw Exception('بيانات فاتورة الشراء غير مكتملة');
    }

    final costPiasters = (costEgp * 100).round();
    final totalPiasters = costPiasters * qty;
    final now = DateTime.now();

    return _db.transaction(() async {
      final branchId = await _resolveBranchId();

      // Match or create supplier
      final suppliers = await (_db.select(_db.suppliers)
            ..where((s) => s.deletedAt.isNull()))
          .get();
      final normSup = OfflineSmartAssistantService.normalizeArabic(supplierName);
      Supplier? matchedSup;
      for (final s in suppliers) {
        if (OfflineSmartAssistantService.normalizeArabic(s.name) == normSup ||
            OfflineSmartAssistantService.normalizeArabic(s.name).contains(normSup)) {
          matchedSup = s;
          break;
        }
      }
      final String supplierId;
      if (matchedSup != null) {
        supplierId = matchedSup.id;
        if (isCredit) {
          await (_db.update(_db.suppliers)
                ..where((s) => s.id.equals(supplierId)))
              .write(
            SuppliersCompanion(
              balance: Value(matchedSup.balance + totalPiasters),
              updatedAt: Value(now),
            ),
          );
        }
      } else {
        supplierId = _genId('sup');
        await _db.into(_db.suppliers).insert(
              SuppliersCompanion.insert(
                id: supplierId,
                branchId: branchId,
                name: supplierName,
                balance: Value(isCredit ? totalPiasters : 0),
                createdAt: now,
                updatedAt: now,
              ),
            );
      }

      // Match or create product + variant
      final products = await (_db.select(_db.products)
            ..where((p) => p.deletedAt.isNull()))
          .get();
      final normProd = OfflineSmartAssistantService.normalizeArabic(productName);
      Product? matchedProd;
      for (final p in products) {
        if (OfflineSmartAssistantService.normalizeArabic(p.name) == normProd ||
            OfflineSmartAssistantService.normalizeArabic(p.name).contains(normProd)) {
          matchedProd = p;
          break;
        }
      }

      final String variantId;
      if (matchedProd != null) {
        final variants = await (_db.select(_db.productVariants)
              ..where((v) =>
                  v.productId.equals(matchedProd!.id) & v.deletedAt.isNull()))
            .get();
        if (variants.isNotEmpty) {
          final v = variants.first;
          variantId = v.id;
          await (_db.update(_db.productVariants)
                ..where((t) => t.id.equals(variantId)))
              .write(
            ProductVariantsCompanion(
              quantity: Value(v.quantity + qty),
              costPrice: Value(costPiasters),
              updatedAt: Value(now),
            ),
          );
        } else {
          variantId = _genId('var');
          await _db.into(_db.productVariants).insert(
                ProductVariantsCompanion.insert(
                  id: variantId,
                  branchId: branchId,
                  productId: matchedProd.id,
                  sku: 'SKU-${now.millisecondsSinceEpoch}',
                  color: '-',
                  size: '-',
                  quantity: Value(qty),
                  costPrice: costPiasters,
                  sellPrice: (costPiasters * 1.3).round(),
                  createdAt: now,
                  updatedAt: now,
                ),
              );
        }
      } else {
        final catId = await _ensureDefaultCategoryId(branchId, now);
        final prodId = _genId('prd');
        await _db.into(_db.products).insert(
              ProductsCompanion.insert(
                id: prodId,
                branchId: branchId,
                name: productName,
                categoryId: catId,
                createdAt: now,
                updatedAt: now,
              ),
            );
        variantId = _genId('var');
        await _db.into(_db.productVariants).insert(
              ProductVariantsCompanion.insert(
                id: variantId,
                branchId: branchId,
                productId: prodId,
                sku: 'SKU-${now.millisecondsSinceEpoch}',
                color: '-',
                size: '-',
                quantity: Value(qty),
                costPrice: costPiasters,
                sellPrice: (costPiasters * 1.3).round(),
                createdAt: now,
                updatedAt: now,
              ),
            );
      }

      // Insert Purchase & PurchaseItem
      final purchaseId = _genId('pur');
      await _db.into(_db.purchases).insert(
            PurchasesCompanion.insert(
              id: purchaseId,
              branchId: branchId,
              supplierId: supplierId,
              invoiceNumber: Value('PUR-${now.millisecondsSinceEpoch % 100000}'),
              purchaseDate: now,
              totalAmount: totalPiasters,
              paidAmount: Value(isCredit ? 0 : totalPiasters),
              status: const Value('received'),
              paymentStatus: Value(isCredit ? 'unpaid' : 'paid'),
              notes: const Value('تم التسجيل عبر المساعد الذكي'),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await _db.into(_db.purchaseItems).insert(
            PurchaseItemsCompanion.insert(
              id: _genId('pi'),
              purchaseId: purchaseId,
              variantId: variantId,
              qty: qty,
              costPrice: costPiasters,
              totalCost: totalPiasters,
              createdAt: now,
            ),
          );

      // Stock movement (InventoryLogs) + AuditLog
      await _db.into(_db.inventoryLogs).insert(
            InventoryLogsCompanion.insert(
              id: _genId('inv'),
              branchId: branchId,
              variantId: variantId,
              type: 'purchase',
              qtyDelta: qty,
              refType: 'purchase',
              refId: Value(purchaseId),
              reason: Value('شراء من $supplierName'),
              userId: userId,
              createdAt: now,
            ),
          );
      await _insertAudit(
        branchId: branchId,
        userId: userId,
        action: 'assistant_record_purchase',
        entity: 'purchase',
        entityId: purchaseId,
        newValue:
            '$productName x$qty @ ${Money(costPiasters).toDisplay()} (${isCredit ? 'credit' : 'cash'})',
        now: now,
      );

      return 'تم تسجيل فاتورة شراء "$productName" ($qty قطعة من $supplierName) بإجمالي ${Money(totalPiasters).toDisplay()} ج.م (${isCredit ? 'آجل على حساب المورد' : 'نقدي'}).';
    });
  }

  Future<String> _execAddProduct(
    Map<String, dynamic> payload, {
    required String userId,
  }) async {
    final name = (payload['productName'] as String? ?? '').trim();
    final costEgp = (payload['costEgp'] as num?)?.toDouble() ?? 0;
    final sellEgp = (payload['sellEgp'] as num?)?.toDouble() ?? 0;
    final qty = (payload['qty'] as num?)?.toInt() ?? 0;

    if (name.isEmpty || costEgp < 0 || sellEgp <= 0 || qty < 0) {
      throw Exception('بيانات الصنف الجديد غير مكتملة');
    }

    final costPiasters = (costEgp * 100).round();
    final sellPiasters = (sellEgp * 100).round();
    final now = DateTime.now();

    return _db.transaction(() async {
      final branchId = await _resolveBranchId();
      final catId = await _ensureDefaultCategoryId(branchId, now);
      final prodId = _genId('prd');
      final varId = _genId('var');

      await _db.into(_db.products).insert(
            ProductsCompanion.insert(
              id: prodId,
              branchId: branchId,
              name: name,
              categoryId: catId,
              createdAt: now,
              updatedAt: now,
            ),
          );
      await _db.into(_db.productVariants).insert(
            ProductVariantsCompanion.insert(
              id: varId,
              branchId: branchId,
              productId: prodId,
              sku: 'SKU-${now.millisecondsSinceEpoch}',
              color: '-',
              size: '-',
              quantity: Value(qty),
              costPrice: costPiasters,
              sellPrice: sellPiasters,
              createdAt: now,
              updatedAt: now,
            ),
          );
      if (qty > 0) {
        await _db.into(_db.inventoryLogs).insert(
              InventoryLogsCompanion.insert(
                id: _genId('inv'),
                branchId: branchId,
                variantId: varId,
                type: 'initial_stock',
                qtyDelta: qty,
                refType: 'product',
                refId: Value(prodId),
                reason: const Value('إضافة صنف عبر المساعد الذكي'),
                userId: userId,
                createdAt: now,
              ),
            );
      }
      await _insertAudit(
        branchId: branchId,
        userId: userId,
        action: 'assistant_add_product',
        entity: 'product',
        entityId: prodId,
        newValue:
            '$name | تكلفة: ${Money(costPiasters).toDisplay()} | بيع: ${Money(sellPiasters).toDisplay()} | كمية: $qty',
        now: now,
      );
      lastUndoToken = AssistantUndoToken(
        kind: AssistantCommandKind.addProduct,
        recordId: prodId,
        label: 'إضافة صنف: $name',
      );

      return 'تمت إضافة الصنف "$name" (تكلفة ${Money(costPiasters).toDisplay()}، بيع ${Money(sellPiasters).toDisplay()} ج.م، رصيد $qty) بنجاح.';
    });
  }

  Future<String> _execUpdateProductPriceOrStock(
    Map<String, dynamic> payload, {
    required String userId,
  }) async {
    final mode = (payload['mode'] as String? ?? 'price').trim();
    final productName = (payload['productName'] as String? ?? '').trim();
    final numVal = (payload['value'] as num?)?.toDouble() ?? 0;

    if (productName.isEmpty) {
      throw Exception('اسم الصنف مطلوب');
    }

    final now = DateTime.now();
    return _db.transaction(() async {
      final branchId = await _resolveBranchId();
      final products = await (_db.select(_db.products)
            ..where((p) => p.deletedAt.isNull()))
          .get();
      final norm = OfflineSmartAssistantService.normalizeArabic(productName);
      Product? targetProd;
      for (final p in products) {
        if (OfflineSmartAssistantService.normalizeArabic(p.name) == norm ||
            OfflineSmartAssistantService.normalizeArabic(p.name).contains(norm)) {
          targetProd = p;
          break;
        }
      }
      if (targetProd == null) {
        throw Exception('لم يتم العثور على صنف باسم "$productName"');
      }

      final variants = await (_db.select(_db.productVariants)
            ..where((v) =>
                v.productId.equals(targetProd!.id) & v.deletedAt.isNull()))
          .get();
      if (variants.isEmpty) {
        throw Exception('لا توجد وحدات متاحة للصنف "${targetProd.name}"');
      }
      final v = variants.first;

      if (mode == 'price') {
        final newSellPiasters = (numVal * 100).round();
        if (newSellPiasters <= 0) {
          throw Exception('سعر البيع يجب أن يكون أكبر من صفر');
        }
        await (_db.update(_db.productVariants)
              ..where((t) => t.id.equals(v.id)))
            .write(
          ProductVariantsCompanion(
            sellPrice: Value(newSellPiasters),
            updatedAt: Value(now),
          ),
        );
        await _insertAudit(
          branchId: branchId,
          userId: userId,
          action: 'assistant_update_price',
          entity: 'product_variant',
          entityId: v.id,
          oldValue: Money(v.sellPrice).toDisplay(),
          newValue: Money(newSellPiasters).toDisplay(),
          now: now,
        );
        return 'تم تعديل سعر بيع "${targetProd.name}" إلى ${Money(newSellPiasters).toDisplay()} ج.م.';
      } else {
        final delta = numVal.round();
        final nextQty = v.quantity + delta;
        if (nextQty < 0) {
          throw Exception('الرصيد الناتج لا يمكن أن يكون سالباً');
        }
        await (_db.update(_db.productVariants)
              ..where((t) => t.id.equals(v.id)))
            .write(
          ProductVariantsCompanion(
            quantity: Value(nextQty),
            updatedAt: Value(now),
          ),
        );
        await _db.into(_db.inventoryLogs).insert(
              InventoryLogsCompanion.insert(
                id: _genId('inv'),
                branchId: branchId,
                variantId: v.id,
                type: 'adjustment',
                qtyDelta: delta,
                refType: 'product',
                refId: Value(targetProd.id),
                reason: const Value('تعديل رصيد عبر المساعد الذكي'),
                userId: userId,
                createdAt: now,
              ),
            );
        await _insertAudit(
          branchId: branchId,
          userId: userId,
          action: 'assistant_adjust_stock',
          entity: 'product_variant',
          entityId: v.id,
          oldValue: '${v.quantity}',
          newValue: '$nextQty',
          now: now,
        );
        return 'تم تحديث رصيد "${targetProd.name}" إلى $nextQty قطعة.';
      }
    });
  }

  Future<String> _execRecordExpense(
    Map<String, dynamic> payload, {
    required String userId,
  }) async {
    final category = (payload['category'] as String? ?? '').trim();
    final amountEgp = (payload['amountEgp'] as num?)?.toDouble() ?? 0;
    if (category.isEmpty || amountEgp <= 0) {
      throw Exception('بيانات المصروف غير مكتملة');
    }
    final amountPiasters = (amountEgp * 100).round();
    final now = DateTime.now();

    return _db.transaction(() async {
      final branchId = await _resolveBranchId();
      final expId = _genId('exp');
      await _db.into(_db.expenses).insert(
            ExpensesCompanion.insert(
              id: expId,
              branchId: branchId,
              category: category,
              amount: amountPiasters,
              kind: const Value('operating'),
              note: const Value('تم التسجيل عبر المساعد الذكي'),
              userId: userId,
              expenseDate: now,
              createdAt: now,
              updatedAt: now,
            ),
          );
      await _insertAudit(
        branchId: branchId,
        userId: userId,
        action: 'assistant_record_expense',
        entity: 'expense',
        entityId: expId,
        newValue: '$category: ${Money(amountPiasters).toDisplay()}',
        now: now,
      );
      lastUndoToken = AssistantUndoToken(
        kind: AssistantCommandKind.recordExpense,
        recordId: expId,
        label: 'مصروف $category (${Money(amountPiasters).toDisplay()} ج.م)',
      );
      return 'تم تسجيل مصروف "$category" بمبلغ ${Money(amountPiasters).toDisplay()} ج.م بنجاح.';
    });
  }

  Future<String> _execPaySupplier(
    Map<String, dynamic> payload, {
    required String userId,
  }) async {
    final supplierName = (payload['supplierName'] as String? ?? '').trim();
    final amountEgp = (payload['amountEgp'] as num?)?.toDouble() ?? 0;
    if (supplierName.isEmpty || amountEgp <= 0) {
      throw Exception('بيانات سداد المورد غير مكتملة');
    }
    final amountPiasters = (amountEgp * 100).round();
    final now = DateTime.now();

    return _db.transaction(() async {
      final branchId = await _resolveBranchId();
      final suppliers = await (_db.select(_db.suppliers)
            ..where((s) => s.deletedAt.isNull()))
          .get();
      final norm = OfflineSmartAssistantService.normalizeArabic(supplierName);
      Supplier? targetSup;
      for (final s in suppliers) {
        if (OfflineSmartAssistantService.normalizeArabic(s.name) == norm ||
            OfflineSmartAssistantService.normalizeArabic(s.name).contains(norm)) {
          targetSup = s;
          break;
        }
      }
      if (targetSup == null) {
        throw Exception('لم يتم العثور على مورد باسم "$supplierName"');
      }

      final newBalance = targetSup.balance - amountPiasters;
      final payId = _genId('spay');
      await _db.into(_db.supplierPayments).insert(
            SupplierPaymentsCompanion.insert(
              id: payId,
              branchId: branchId,
              supplierId: targetSup.id,
              amount: amountPiasters,
              paymentDate: now,
              paymentMethod: const Value('cash'),
              notes: const Value('سداد عبر المساعد الذكي'),
              createdBy: userId,
              createdAt: now,
            ),
          );
      await (_db.update(_db.suppliers)
            ..where((s) => s.id.equals(targetSup!.id)))
          .write(
        SuppliersCompanion(
          balance: Value(newBalance),
          updatedAt: Value(now),
        ),
      );
      await _insertAudit(
        branchId: branchId,
        userId: userId,
        action: 'assistant_pay_supplier',
        entity: 'supplier_payment',
        entityId: payId,
        oldValue: Money(targetSup.balance).toDisplay(),
        newValue: Money(newBalance).toDisplay(),
        now: now,
      );
      return 'تم تسجيل سداد ${Money(amountPiasters).toDisplay()} ج.م للمورد "${targetSup.name}"؛ الرصيد الحالي: ${Money(newBalance).toDisplay()} ج.م.';
    });
  }

  /// Strips repeated conversational Arabic prefixes and normalizes colloquial
  /// verbs and nouns into canonical ERP command forms while preserving original
  /// Arabic letter forms (ة/أ/إ/ى) for extracted entity names.
  String _stripConversationalPrefixes(String input) {
    var s = Money.normalizeDigits(input).trim();
    final prefixRegex = RegExp(
      r'^(?:عايز|عاوز|محتاج|ممكن|لو\s+سمحت|ياريت|يا\s+ريت|حابب|[أا]ريد|[أا]بغ[يى]|[أا]نا|[إا]حنا|دلوقتي|بسرع[ةه]|ع\s+السريع|[إا]ني|[إا]ن)(?=\s|$)\s*',
    );
    while (true) {
      final next = s.replaceFirst(prefixRegex, '').trim();
      if (next == s) break;
      s = next;
    }

    const verbRules = <(String, String)>[
      (r'^(?:[أا]ضيف|تضيف|نضيف|هضيف|هاضيف|ضف)(?=\s|$)', 'ضيف'),
      (r'^(?:[أا]سجل|تسجل|نسجل|هسجل|هاسجل|[أا]دخل|تدخل)(?=\s|$)', 'سجل'),
      (r'^(?:[أا]عدل|تعدل|نعدل|[أا]غير|تغير|[أا]خلي|تخلي)(?=\s|$)', 'عدل'),
      (r'^(?:[أا]زود|تزود|نزود|هزود)(?=\s|$)', 'زود'),
      (r'^(?:[أا]نقص|تنقص|نخصم|[أا]قلل)(?=\s|$)', 'نقص'),
      (r'^(?:[أا]دفع|تدفع|سددت|بسدد)(?=\s|$)', 'دفعت'),
      (r'^(?:[أا]شتري|بشتري|شريت|جبت)(?=\s|$)', 'اشتريت'),
      (r'^(?:[أا]حصل|تحصل|نحصل|هحصل)(?=\s|$)', 'تحصيل'),
    ];
    for (final (pattern, replacement) in verbRules) {
      final reg = RegExp(pattern);
      if (reg.hasMatch(s)) {
        s = s.replaceFirst(reg, replacement).trim();
        break;
      }
    }

    s = s.replaceAllMapped(
      RegExp(r'(^|\s)زبون(?=\s|$)'),
      (m) => '${m.group(1)}عميل',
    );
    s = s.replaceFirstMapped(
      RegExp(r'^(ضيف|[أا]ضف|[إا]ضاف[ةه])\s+(?:منتج|بضاع[ةه]|موديل)(?=\s|$)'),
      (m) => '${m.group(1)} صنف',
    );
    return s.trim();
  }

  /// Parses ERP operational commands into a (possibly incomplete) [AssistantActionDraft].
  final AssistantContextMemory contextMemory = AssistantContextMemory();
  AssistantUndoToken? lastUndoToken;

  Future<String> undoLastCommand({
    required String userId,
    required String userRole,
  }) async {
    if (userRole != 'admin') {
      throw Exception('عذراً: التراجع عن العمليات متاح لحساب المدير (Admin) فقط.');
    }
    final token = lastUndoToken;
    if (token == null) {
      throw Exception('لا توجد عملية حديثة قابلة للتراجع.');
    }
    final now = DateTime.now();
    await _db.transaction(() async {
      final branchId = await _resolveBranchId();
      switch (token.kind) {
        case AssistantCommandKind.recordExpense:
          await (_db.update(_db.expenses)
                ..where((e) => e.id.equals(token.recordId)))
              .write(ExpensesCompanion(deletedAt: Value(now)));
          break;
        case AssistantCommandKind.addCustomer:
          await (_db.update(_db.customers)
                ..where((c) => c.id.equals(token.recordId)))
              .write(CustomersCompanion(deletedAt: Value(now)));
          break;
        case AssistantCommandKind.addProduct:
          await (_db.update(_db.products)
                ..where((p) => p.id.equals(token.recordId)))
              .write(ProductsCompanion(deletedAt: Value(now)));
          await (_db.update(_db.productVariants)
                ..where((v) => v.productId.equals(token.recordId)))
              .write(ProductVariantsCompanion(deletedAt: Value(now)));
          break;
        default:
          throw Exception('هذه العملية لا تدعم التراجع التلقائي.');
      }
      await _insertAudit(
        branchId: branchId,
        userId: userId,
        action: 'assistant_undo_${token.kind.name}',
        entity: token.kind.name,
        entityId: token.recordId,
        oldValue: token.label,
        newValue: 'reverted',
        now: now,
      );
    });
    lastUndoToken = null;
    return 'تم التراجع عن العملية (${token.label}) بنجاح.';
  }

  AssistantCommandKind? _commandKindForNluIntent(AssistantNluIntent intent) {
    switch (intent) {
      case AssistantNluIntent.addProduct:
        return AssistantCommandKind.addProduct;
      case AssistantNluIntent.recordPurchase:
        return AssistantCommandKind.recordPurchase;
      case AssistantNluIntent.recordExpense:
        return AssistantCommandKind.recordExpense;
      case AssistantNluIntent.paySupplier:
        return AssistantCommandKind.paySupplier;
      case AssistantNluIntent.addCustomer:
        return AssistantCommandKind.addCustomer;
      case AssistantNluIntent.collectInstallment:
        return AssistantCommandKind.collectInstallment;
      case AssistantNluIntent.updatePrice:
      case AssistantNluIntent.updateStock:
        return AssistantCommandKind.updateProductPriceOrStock;
      case AssistantNluIntent.calculateZakat:
        return AssistantCommandKind.calculateZakat;
      default:
        return null;
    }
  }

  AssistantActionDraft? parseErpDraft(String rawQuery) {
    final rawDigits = Money.normalizeDigits(rawQuery).trim();
    final rawNorm = OfflineSmartAssistantService.normalizeArabic(rawDigits);
    if (rawNorm.contains('ازاي') ||
        rawNorm.contains('كيف') ||
        rawNorm.contains('خطوات') ||
        rawNorm.contains('طريقه')) {
      return null;
    }

    final nluResult = AssistantIntentScorer.score(
      rawDigits,
      context: contextMemory,
    );
    if (nluResult != null) {
      final mappedKind = _commandKindForNluIntent(nluResult.intent);
      if (mappedKind != null) {
        final draft = _finalizeDraft(mappedKind, nluResult.slots);
        contextMemory.updateFromDraft(
          intent: nluResult.intent,
          fields: draft.fields,
        );
        return draft;
      }
    }

    final cleanedDigits = _stripConversationalPrefixes(rawDigits);
    final q = OfflineSmartAssistantService.normalizeArabic(cleanedDigits);

    // 0. Add Customer: "ضيف عميل [اسم] [رقم هاتف]"
    if (q.startsWith('ضيف عميل') ||
        q.startsWith('اضف عميل') ||
        q.startsWith('اضافه عميل') ||
        q.startsWith('عميل جديد')) {
      var body = cleanedDigits
          .replaceFirst(
            RegExp(r'^(?:ضيف\s+عميل|[أا]ضف\s+عميل|[إا]ضاف[ةه]\s+عميل|عميل\s+جديد)\s*'),
            '',
          )
          .trim();
      if (body == 'جديد') body = '';
      final phoneMatch = RegExp(r'(\+?\d{8,15})$').firstMatch(body);
      String? phone;
      String? custName;
      if (phoneMatch != null) {
        phone = phoneMatch.group(1)!.trim();
        custName = body.substring(0, phoneMatch.start).trim();
      } else if (body.isNotEmpty) {
        custName = body;
      }
      final fields = <String, dynamic>{
        if (custName != null && custName.isNotEmpty) 'customerName': custName,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
      };
      return _finalizeDraft(AssistantCommandKind.addCustomer, fields);
    }

    // 0b. Collect Installment: "العميل [اسم] دفع قسط [مبلغ]" / "تحصيل قسط [اسم] [مبلغ]"
    if (q.contains('دفع قسط') || q.startsWith('تحصيل قسط')) {
      String body = cleanedDigits;
      double? amount;
      String? custName;
      final custPayMatch = RegExp(
        r'^(?:العميل\s+)?(.+?)\s+دفع\s+قسط(?:\s+(\d+(?:\.\d+)?))?',
      ).firstMatch(body);
      if (custPayMatch != null) {
        custName = custPayMatch.group(1)?.trim();
        if (custPayMatch.group(2) != null) {
          amount = double.tryParse(custPayMatch.group(2)!);
        }
      } else {
        body = body.replaceFirst(RegExp(r'^تحصيل\s+قسط\s*'), '').trim();
        final amtMatch = RegExp(r'(\d+(?:\.\d+)?)\s*(?:ج\.?م|جنيه)?$').firstMatch(body);
        if (amtMatch != null) {
          amount = double.tryParse(amtMatch.group(1)!);
          custName = body.substring(0, amtMatch.start).trim();
        } else if (body.isNotEmpty) {
          custName = body;
        }
      }
      final fields = <String, dynamic>{
        if (custName != null && custName.isNotEmpty) 'customerName': custName,
        if (amount != null && amount > 0) 'amountEgp': amount,
      };
      return _finalizeDraft(AssistantCommandKind.collectInstallment, fields);
    }

    // 0c. Zakat Calculator Draft: "احسب الزكاة" / "زكاة المال" / "زكاة التجارة"
    if (q.contains('احسب الزكاه') ||
        q.contains('زكاه المال') ||
        q.contains('زكاه التجاره') ||
        q.contains('حاسبه الزكاه') ||
        q == 'الزكاه') {
      final isGregorian = q.contains('ميلادي');
      final goldMatch = RegExp(
        r'(?:الذهب|ذهب|عيار\s*24|سعر)\s*(?:ب|هو)?\s*(\d+(?:\.\d+)?)',
      ).firstMatch(cleanedDigits);
      double? goldPrice =
          goldMatch != null ? double.tryParse(goldMatch.group(1)!) : null;
      if (goldPrice == null) {
        final trailingNum = RegExp(r'(\d{3,6}(?:\.\d+)?)\s*(?:ج\.?م|جنيه)?$')
            .firstMatch(cleanedDigits);
        if (trailingNum != null) {
          goldPrice = double.tryParse(trailingNum.group(1)!);
        }
      }
      final fields = <String, dynamic>{
        if (goldPrice != null && goldPrice > 0) 'goldPrice24': goldPrice,
        'isGregorianYear': isGregorian,
      };
      return _finalizeDraft(AssistantCommandKind.calculateZakat, fields);
    }

    // 1. Pay Supplier: "دفعت للمورد [اسم] [مبلغ]" / "سداد مورد [اسم] [مبلغ]"
    if (q.startsWith('دفعت للمورد') ||
        q.startsWith('دفعت لمورد') ||
        q.startsWith('سداد مورد') ||
        q.startsWith('سدد للمورد')) {
      final body = cleanedDigits
          .replaceFirst(
            RegExp(r'^(?:دفعت\s+(?:للمورد|لمورد)|سداد\s+مورد|سدد\s+للمورد)\s*'),
            '',
          )
          .trim();
      final amtMatch = RegExp(r'(\d+(?:\.\d+)?)\s*(?:ج\.?م|جنيه)?$').firstMatch(body);
      double? amount;
      String? supName;
      if (amtMatch != null) {
        amount = double.tryParse(amtMatch.group(1)!);
        supName = body.substring(0, amtMatch.start).trim();
      } else if (body.isNotEmpty) {
        supName = body;
      }
      final fields = <String, dynamic>{
        if (supName != null && supName.isNotEmpty) 'supplierName': supName,
        if (amount != null && amount > 0) 'amountEgp': amount,
      };
      return _finalizeDraft(AssistantCommandKind.paySupplier, fields);
    }

    // 2. Record Expense: "سجل مصروف [بند] [مبلغ]" / "دفعت [بند] [مبلغ]"
    if (q.startsWith('سجل مصروف') ||
        q.startsWith('اضف مصروف') ||
        q.startsWith('مصروف جديد') ||
        (q.startsWith('دفعت ') && !q.contains('مورد'))) {
      final body = cleanedDigits
          .replaceFirst(
            RegExp(r'^(?:سجل\s+مصروف|[أا]ضف\s+مصروف|مصروف\s+جديد|دفعت)\s*'),
            '',
          )
          .trim();
      final amtMatch = RegExp(r'(\d+(?:\.\d+)?)\s*(?:ج\.?م|جنيه)?$').firstMatch(body);
      double? amount;
      String? category;
      if (amtMatch != null) {
        amount = double.tryParse(amtMatch.group(1)!);
        category = body.substring(0, amtMatch.start).trim();
      } else if (body.isNotEmpty) {
        category = body;
      }
      final fields = <String, dynamic>{
        if (category != null && category.isNotEmpty) 'category': category,
        if (amount != null && amount > 0) 'amountEgp': amount,
      };
      return _finalizeDraft(AssistantCommandKind.recordExpense, fields);
    }

    // 3. Update Product Price or Stock: "خلي سعر [صنف] [سعر]" / "زود رصيد [صنف] [عدد]"
    if (q.startsWith('خلي سعر ') ||
        q.startsWith('عدل سعر ') ||
        q.startsWith('غير سعر ')) {
      final body = cleanedDigits
          .replaceFirst(RegExp(r'^(?:خلي|عدل|غير|عدّل)\s+سعر\s+'), '')
          .trim();
      final numMatch = RegExp(r'(?:\s+(?:لـ?|إلى|الى|بـ?))?\s*(\d+(?:\.\d+)?)\s*(?:ج\.?م|جنيه)?$').firstMatch(body);
      double? val;
      String? prodName;
      if (numMatch != null) {
        val = double.tryParse(numMatch.group(1)!);
        prodName = body
            .substring(0, numMatch.start)
            .replaceFirst(RegExp(r'\s+(?:لـ?|إلى|الى|بـ?)$'), '')
            .trim();
      } else if (body.isNotEmpty) {
        prodName = body;
      }
      final fields = <String, dynamic>{
        'mode': 'price',
        if (prodName != null && prodName.isNotEmpty) 'productName': prodName,
        if (val != null && val > 0) 'value': val,
      };
      return _finalizeDraft(AssistantCommandKind.updateProductPriceOrStock, fields);
    }
    if (q.startsWith('زود رصيد ') ||
        q.startsWith('زود كميه ') ||
        q.startsWith('نقص رصيد ')) {
      final isNeg = q.startsWith('نقص');
      final body = cleanedDigits
          .replaceFirst(RegExp(r'^(?:زود|نقص)\s+(?:رصيد|كمي[ةه])\s+'), '')
          .trim();
      final numMatch = RegExp(r'(\d+)\s*(?:قطع[ةه])?$').firstMatch(body);
      int? val;
      String? prodName;
      if (numMatch != null) {
        val = int.tryParse(numMatch.group(1)!);
        if (val != null && isNeg) val = -val;
        prodName = body.substring(0, numMatch.start).trim();
      } else if (body.isNotEmpty) {
        prodName = body;
      }
      final fields = <String, dynamic>{
        'mode': 'stock',
        if (prodName != null && prodName.isNotEmpty) 'productName': prodName,
        if (val != null && val != 0) 'value': val,
      };
      return _finalizeDraft(AssistantCommandKind.updateProductPriceOrStock, fields);
    }

    // 4. Add Product: "ضيف صنف [اسم] تكلفة [سعر] بيع [سعر] كمية [عدد]"
    if (q.startsWith('ضيف صنف') ||
        q.startsWith('اضف صنف') ||
        q.startsWith('اضافه صنف') ||
        q.startsWith('صنف جديد')) {
      final body = cleanedDigits
          .replaceFirst(
            RegExp(r'^(?:ضيف\s+صنف|[أا]ضف\s+صنف|[إا]ضاف[ةه]\s+صنف|صنف\s+جديد)\s*'),
            '',
          )
          .trim();
      final costMatch = RegExp(r'تكلف[ةه]\s+(\d+(?:\.\d+)?)').firstMatch(body);
      final sellMatch = RegExp(r'(?:بيع|سعر)\s+(\d+(?:\.\d+)?)').firstMatch(body);
      final qtyMatch = RegExp(r'(?:كمي[ةه]|عدد)\s+(\d+)').firstMatch(body);

      String prodName = body;
      final cutIndices = [
        if (costMatch != null) costMatch.start,
        if (sellMatch != null) sellMatch.start,
        if (qtyMatch != null) qtyMatch.start,
      ];
      if (cutIndices.isNotEmpty) {
        cutIndices.sort();
        prodName = body.substring(0, cutIndices.first).trim();
      }
      if (prodName == 'جديد') {
        prodName = '';
      }

      final fields = <String, dynamic>{
        if (prodName.isNotEmpty) 'productName': prodName,
        if (costMatch != null) 'costEgp': double.tryParse(costMatch.group(1)!),
        if (sellMatch != null) 'sellEgp': double.tryParse(sellMatch.group(1)!),
        if (qtyMatch != null) 'qty': int.tryParse(qtyMatch.group(1)!),
      }..removeWhere((_, v) => v == null);
      return _finalizeDraft(AssistantCommandKind.addProduct, fields);
    }

    // 5. Record Purchase: "اشتريت [صنف] من المورد [اسم] بسعر [سعر] عدد [كمية] (نقدي/آجل)"
    if (q.startsWith('اشتريت') || q.startsWith('شراء ') || q.startsWith('سجل مشتريات')) {
      final body = cleanedDigits
          .replaceFirst(RegExp(r'^(?:اشتريت|شراء|سجل\s+مشتريات)\s*'), '')
          .trim();
      final isCredit = q.contains('اجل') || q.contains('شكك');
      final supMatch = RegExp(
        r'من\s+(?:المورد|مورد)?\s*([^\d]+?)(?=\s+(?:بسعر|سعر|عدد|كمي[ةه]|نقدي|كاش|[آا]جل)|$)',
      ).firstMatch(body);
      final costMatch = RegExp(r'(?:بسعر|سعر)\s+(\d+(?:\.\d+)?)').firstMatch(body);
      final qtyMatch = RegExp(r'(?:عدد|كمي[ةه])\s+(\d+)').firstMatch(body);

      String prodName = body;
      final cutIndices = [
        if (supMatch != null) supMatch.start,
        if (costMatch != null) costMatch.start,
        if (qtyMatch != null) qtyMatch.start,
      ];
      if (cutIndices.isNotEmpty) {
        cutIndices.sort();
        prodName = body.substring(0, cutIndices.first).trim();
      }
      if (prodName == 'بضاعة' || prodName == 'بضاعه' || prodName == 'صنف' || prodName == 'جديد') {
        prodName = '';
      }

      final fields = <String, dynamic>{
        if (prodName.isNotEmpty) 'productName': prodName,
        if (supMatch != null && supMatch.group(1)!.trim().isNotEmpty)
          'supplierName': supMatch.group(1)!.trim(),
        if (costMatch != null) 'costEgp': double.tryParse(costMatch.group(1)!),
        if (qtyMatch != null) 'qty': int.tryParse(qtyMatch.group(1)!),
        'paymentType': isCredit ? 'credit' : 'cash',
      }..removeWhere((_, v) => v == null);
      return _finalizeDraft(AssistantCommandKind.recordPurchase, fields);
    }

    return null;
  }

  AssistantActionDraft _finalizeDraft(
    AssistantCommandKind kind,
    Map<String, dynamic> fields,
  ) {
    switch (kind) {
      case AssistantCommandKind.recordPurchase:
        if ((fields['productName'] as String? ?? '').isEmpty) {
          return AssistantActionDraft(
            kind: kind,
            fields: fields,
            missingField: 'productName',
            promptForMissing: 'ما اسم الصنف الذي اشتريته؟',
          );
        }
        if ((fields['supplierName'] as String? ?? '').isEmpty) {
          return AssistantActionDraft(
            kind: kind,
            fields: fields,
            missingField: 'supplierName',
            promptForMissing: 'من أي مورد اشتريت الصنف؟',
          );
        }
        if ((fields['costEgp'] as num? ?? 0) <= 0) {
          return AssistantActionDraft(
            kind: kind,
            fields: fields,
            missingField: 'costEgp',
            promptForMissing: 'كم سعر شراء القطعة الواحدة بالجنيه؟',
          );
        }
        if ((fields['qty'] as num? ?? 0) <= 0) {
          return AssistantActionDraft(
            kind: kind,
            fields: fields,
            missingField: 'qty',
            promptForMissing: 'كم الكمية المشتراة (عدد القطع)؟',
          );
        }
        return AssistantActionDraft(kind: kind, fields: fields);

      case AssistantCommandKind.addProduct:
        if ((fields['productName'] as String? ?? '').isEmpty) {
          return AssistantActionDraft(
            kind: kind,
            fields: fields,
            missingField: 'productName',
            promptForMissing: 'ما اسم الصنف الجديد؟',
          );
        }
        if (fields['costEgp'] == null) {
          return AssistantActionDraft(
            kind: kind,
            fields: fields,
            missingField: 'costEgp',
            promptForMissing: 'كم سعر التكلفة للصنف الجديد بالجنيه؟',
          );
        }
        if ((fields['sellEgp'] as num? ?? 0) <= 0) {
          return AssistantActionDraft(
            kind: kind,
            fields: fields,
            missingField: 'sellEgp',
            promptForMissing: 'كم سعر البيع المقترح بالجنيه؟',
          );
        }
        if (fields['qty'] == null) {
          return AssistantActionDraft(
            kind: kind,
            fields: fields,
            missingField: 'qty',
            promptForMissing: 'كم الكمية الافتتاحية بالمخزن؟',
          );
        }
        return AssistantActionDraft(kind: kind, fields: fields);

      case AssistantCommandKind.updateProductPriceOrStock:
        final isPrice = (fields['mode'] ?? 'price') == 'price';
        if ((fields['productName'] as String? ?? '').isEmpty) {
          return AssistantActionDraft(
            kind: kind,
            fields: fields,
            missingField: 'productName',
            promptForMissing: 'ما اسم الصنف المراد تعديله؟',
          );
        }
        if (fields['value'] == null) {
          return AssistantActionDraft(
            kind: kind,
            fields: fields,
            missingField: 'value',
            promptForMissing:
                isPrice ? 'ما السعر الجديد بالجنيه؟' : 'كم الكمية المراد إضافتها/خصمها؟',
          );
        }
        return AssistantActionDraft(kind: kind, fields: fields);

      case AssistantCommandKind.recordExpense:
        if ((fields['category'] as String? ?? '').isEmpty) {
          return AssistantActionDraft(
            kind: kind,
            fields: fields,
            missingField: 'category',
            promptForMissing: 'ما بند المصروف (مثال: كهرباء، إيجار، ضيافة)؟',
          );
        }
        if ((fields['amountEgp'] as num? ?? 0) <= 0) {
          return AssistantActionDraft(
            kind: kind,
            fields: fields,
            missingField: 'amountEgp',
            promptForMissing: 'كم مبلغ المصروف بالجنيه؟',
          );
        }
        return AssistantActionDraft(kind: kind, fields: fields);

      case AssistantCommandKind.paySupplier:
        if ((fields['supplierName'] as String? ?? '').isEmpty) {
          return AssistantActionDraft(
            kind: kind,
            fields: fields,
            missingField: 'supplierName',
            promptForMissing: 'ما اسم المورد المراد السداد له؟',
          );
        }
        if ((fields['amountEgp'] as num? ?? 0) <= 0) {
          return AssistantActionDraft(
            kind: kind,
            fields: fields,
            missingField: 'amountEgp',
            promptForMissing: 'كم المبلغ المدفوع للمورد بالجنيه؟',
          );
        }
        return AssistantActionDraft(kind: kind, fields: fields);

      case AssistantCommandKind.addCustomer:
        if ((fields['customerName'] as String? ?? '').isEmpty) {
          return AssistantActionDraft(
            kind: kind,
            fields: fields,
            missingField: 'customerName',
            promptForMissing: 'ما اسم العميل الجديد؟',
          );
        }
        if ((fields['phone'] as String? ?? '').isEmpty) {
          return AssistantActionDraft(
            kind: kind,
            fields: fields,
            missingField: 'phone',
            promptForMissing: 'ما رقم هاتف العميل؟',
          );
        }
        return AssistantActionDraft(kind: kind, fields: fields);

      case AssistantCommandKind.collectInstallment:
        if ((fields['customerName'] as String? ?? '').isEmpty) {
          return AssistantActionDraft(
            kind: kind,
            fields: fields,
            missingField: 'customerName',
            promptForMissing: 'ما اسم العميل الذي سدد القسط؟',
          );
        }
        if ((fields['amountEgp'] as num? ?? 0) <= 0) {
          return AssistantActionDraft(
            kind: kind,
            fields: fields,
            missingField: 'amountEgp',
            promptForMissing: 'كم مبلغ القسط المحصل بالجنيه؟',
          );
        }
        return AssistantActionDraft(kind: kind, fields: fields);

      case AssistantCommandKind.calculateZakat:
        if ((fields['goldPrice24'] as num? ?? 0) <= 0) {
          return AssistantActionDraft(
            kind: kind,
            fields: fields,
            missingField: 'goldPrice24',
            promptForMissing:
                'ما سعر جرام الذهب عيار 24 اليوم (بالجنيه)؟ (ويمكنك إضافة كاش بنكي أو ديون خارجية في نفس الرد إن وجدت)',
          );
        }
        return AssistantActionDraft(kind: kind, fields: fields);

      default:
        return AssistantActionDraft(kind: kind, fields: fields);
    }
  }

  AssistantActionDraft advanceDraft(
    AssistantActionDraft draft,
    String userReply,
  ) {
    final cleaned = Money.normalizeDigits(userReply).trim();
    final updated = Map<String, dynamic>.from(draft.fields);
    final missing = draft.missingField;
    if (missing != null && cleaned.isNotEmpty) {
      if (missing == 'goldPrice24') {
        final bankMatch = RegExp(r'(?:بنك|بنكي|خارجي)\s+(\d+(?:\.\d+)?)')
            .firstMatch(cleaned);
        final debtMatch = RegExp(r'(?:دين|ديون|التزامات)\s+(\d+(?:\.\d+)?)')
            .firstMatch(cleaned);
        if (bankMatch != null) {
          updated['extraBankCashEgp'] = double.tryParse(bankMatch.group(1)!);
        }
        if (debtMatch != null) {
          updated['extraDebtsEgp'] = double.tryParse(debtMatch.group(1)!);
        }
        final firstNum = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(cleaned);
        if (firstNum != null) {
          updated['goldPrice24'] = double.tryParse(firstNum.group(1)!);
        }
        if (OfflineSmartAssistantService.normalizeArabic(cleaned).contains('ميلادي')) {
          updated['isGregorianYear'] = true;
        }
      } else if (missing == 'costEgp' ||
          missing == 'sellEgp' ||
          missing == 'amountEgp') {
        final nums = RegExp(r'(\d+(?:\.\d+)?)')
            .allMatches(cleaned)
            .map((m) => double.tryParse(m.group(1)!))
            .whereType<double>()
            .toList();
        if (nums.isNotEmpty) {
          updated[missing] = nums.first;
          // Support compound replies like "150 300 10" or "150 بيع 300 كمية 10"
          if (draft.kind == AssistantCommandKind.addProduct &&
              missing == 'costEgp') {
            final sellMatch = RegExp(r'(?:بيع|سعر)\s+(\d+(?:\.\d+)?)')
                .firstMatch(cleaned);
            final qtyMatch = RegExp(r'(?:كمي[ةه]|عدد)\s+(\d+)')
                .firstMatch(cleaned);
            if (sellMatch != null) {
              updated['sellEgp'] = double.tryParse(sellMatch.group(1)!);
            } else if (nums.length >= 2) {
              updated['sellEgp'] = nums[1];
            }
            if (qtyMatch != null) {
              updated['qty'] = int.tryParse(qtyMatch.group(1)!);
            } else if (nums.length >= 3) {
              updated['qty'] = nums[2].toInt();
            }
          }
        }
      } else if (missing == 'qty' || missing == 'value') {
        final numMatch = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(cleaned);
        if (numMatch != null) {
          updated[missing] = missing == 'qty'
              ? int.tryParse(numMatch.group(1)!.split('.').first)
              : double.tryParse(numMatch.group(1)!);
        }
      } else {
        updated[missing] = cleaned;
      }
    }
    return _finalizeDraft(draft.kind, updated);
  }

  AssistantInsight _buildDraftPromptInsight(AssistantActionDraft draft) {
    final quickChips = <String>[
      if (draft.missingField == 'qty') ...['1', '5', '12'],
      if (draft.missingField == 'amountEgp') ...['100', '200', '500'],
      'إلغاء',
    ];
    return AssistantInsight(
      id: 'draft_prompt_${draft.missingField}',
      title: 'استكمال بيانات العملية',
      summary: draft.promptForMissing ?? 'أدخل القيمة المطلوبة:',
      details: const ['يمكنك كتابة "إلغاء" في أي وقت لإلغاء المسودة.'],
      followUpPrompts: quickChips,
    );
  }

  AssistantInsight _buildPendingCommandInsight(AssistantActionDraft draft) {
    final f = draft.fields;
    switch (draft.kind) {
      case AssistantCommandKind.recordPurchase:
        final prod = f['productName'];
        final sup = f['supplierName'];
        final cost = (f['costEgp'] as num).toDouble();
        final qty = (f['qty'] as num).toInt();
        final isCredit = f['paymentType'] == 'credit';
        final total = cost * qty;
        return AssistantInsight(
          id: 'cmd_record_purchase',
          title: 'تأكيد تسجيل فاتورة مشتريات',
          summary:
              'شراء "$prod" ($qty قطعة) من المورد "$sup" بإجمالي ${total.toStringAsFixed(2)} ج.م (${isCredit ? 'آجل' : 'نقدي'}).',
          details: const ['يتطلب التنفيذ صلاحية مدير (Admin) ويُحفظ في سجل المراجعة.'],
          pendingCommand: AssistantPendingCommand(
            kind: AssistantCommandKind.recordPurchase,
            title: 'تسجيل مشتريات',
            description: '$prod x$qty',
            payload: Map<String, dynamic>.from(f),
          ),
        );
      case AssistantCommandKind.addProduct:
        final prod = f['productName'];
        final cost = (f['costEgp'] as num).toDouble();
        final sell = (f['sellEgp'] as num).toDouble();
        final qty = (f['qty'] as num).toInt();
        return AssistantInsight(
          id: 'cmd_add_product',
          title: 'تأكيد إضافة صنف جديد',
          summary:
              'إضافة "$prod" — تكلفة ${cost.toStringAsFixed(2)} ج.م، بيع ${sell.toStringAsFixed(2)} ج.م، كمية $qty.',
          details: const ['يتطلب التنفيذ صلاحية مدير (Admin).'],
          pendingCommand: AssistantPendingCommand(
            kind: AssistantCommandKind.addProduct,
            title: 'إضافة صنف جديد',
            description: '$prod',
            payload: Map<String, dynamic>.from(f),
          ),
        );
      case AssistantCommandKind.updateProductPriceOrStock:
        final isPrice = (f['mode'] ?? 'price') == 'price';
        final prod = f['productName'];
        final val = (f['value'] as num).toDouble();
        return AssistantInsight(
          id: 'cmd_update_product',
          title: isPrice ? 'تأكيد تعديل سعر الصنف' : 'تأكيد تعديل رصيد الصنف',
          summary: isPrice
              ? 'تعديل سعر بيع "$prod" إلى ${val.toStringAsFixed(2)} ج.م.'
              : 'تعديل رصيد "$prod" بمقدار ${val.toInt()} قطعة.',
          details: const ['يتطلب التنفيذ صلاحية مدير (Admin).'],
          pendingCommand: AssistantPendingCommand(
            kind: AssistantCommandKind.updateProductPriceOrStock,
            title: isPrice ? 'تعديل سعر صنف' : 'تعديل رصيد صنف',
            description: '$prod',
            payload: Map<String, dynamic>.from(f),
          ),
        );
      case AssistantCommandKind.recordExpense:
        final cat = f['category'];
        final amt = (f['amountEgp'] as num).toDouble();
        return AssistantInsight(
          id: 'cmd_record_expense',
          title: 'تأكيد تسجيل مصروف',
          summary: 'تسجيل مصروف "$cat" بمبلغ ${amt.toStringAsFixed(2)} ج.م.',
          details: const ['يتطلب التنفيذ صلاحية مدير (Admin).'],
          pendingCommand: AssistantPendingCommand(
            kind: AssistantCommandKind.recordExpense,
            title: 'تسجيل مصروف',
            description: '$cat',
            payload: Map<String, dynamic>.from(f),
          ),
        );
      case AssistantCommandKind.paySupplier:
        final sup = f['supplierName'];
        final amt = (f['amountEgp'] as num).toDouble();
        return AssistantInsight(
          id: 'cmd_pay_supplier',
          title: 'تأكيد سداد مورد',
          summary: 'تسجيل سداد ${amt.toStringAsFixed(2)} ج.م للمورد "$sup".',
          details: const ['يتطلب التنفيذ صلاحية مدير (Admin).'],
          pendingCommand: AssistantPendingCommand(
            kind: AssistantCommandKind.paySupplier,
            title: 'سداد مورد',
            description: '$sup',
            payload: Map<String, dynamic>.from(f),
          ),
        );
      case AssistantCommandKind.addCustomer:
        final cust = f['customerName'];
        final phone = f['phone'];
        return AssistantInsight(
          id: 'cmd_add_customer',
          title: 'تأكيد إضافة عميل جديد',
          summary: 'إضافة العميل "$cust" برقم هاتف "$phone".',
          details: const ['يتطلب التنفيذ صلاحية مدير أو كاشير مصرح له.'],
          pendingCommand: AssistantPendingCommand(
            kind: AssistantCommandKind.addCustomer,
            title: 'إضافة عميل',
            description: '$cust',
            payload: Map<String, dynamic>.from(f),
          ),
        );
      case AssistantCommandKind.collectInstallment:
        final cust = f['customerName'];
        final amt = (f['amountEgp'] as num).toDouble();
        return AssistantInsight(
          id: 'cmd_collect_installment',
          title: 'تأكيد تحصيل قسط عميل',
          summary: 'تحصيل قسط بقيمة ${amt.toStringAsFixed(2)} ج.م من العميل "$cust".',
          details: const ['سيتم تحديث المتبقي في عقد التقسيط وتسجيل الدفعة.'],
          pendingCommand: AssistantPendingCommand(
            kind: AssistantCommandKind.collectInstallment,
            title: 'تحصيل قسط',
            description: '$cust',
            payload: Map<String, dynamic>.from(f),
          ),
        );
      default:
        return const AssistantInsight(
          id: 'cmd_unknown',
          title: 'أمر غير معروف',
          summary: 'تعذر تجهيز الأمر للتنفيذ.',
        );
    }
  }
}
