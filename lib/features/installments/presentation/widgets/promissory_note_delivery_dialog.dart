import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';

/// Outcomes of the promissory note / receipt delivery check.
enum PromissoryNoteDeliveryResult {
  /// Promissory note / receipt was handed over to the customer.
  delivered,

  /// Promissory note / receipt is still kept in the branch safe (deliver later).
  inSafe,

  /// No promissory note / receipt exists for this customer/contract.
  noReceipt,
}

/// Pops up a standardized confirmation dialog asking if the promissory note / receipt
/// has been handed over to the customer upon full settlement of an installment contract,
/// or if no promissory note was taken for this customer.
Future<PromissoryNoteDeliveryResult?> showPromissoryNoteDeliveryDialog(
  BuildContext context, {
  String? customerName,
  String? contractNumber,
}) {
  return showDialog<PromissoryNoteDeliveryResult>(
    context: context,
    barrierDismissible: false,
    builder: (dialogCtx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.inventory_2_rounded,
              color: AppColors.primary,
              size: 22,
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'تسليم إيصال / وصل الأمانة',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.success.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    color: AppColors.success,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      customerName != null && customerName.isNotEmpty
                          ? 'تم سداد العقد بالكامل للعميل ($customerName) وأصبح الرصيد 0 ج.م.'
                          : 'تم سداد العقد بالكامل بنجاح وأصبح الرصيد 0 ج.م.',
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                        color: AppColors.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'هل تم تسليم أصل إيصال / وصل الأمانة للعميل الآن؟',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'إذا كان الوصل ما زال في الخزينة يمكنك حفظه لتسليمه لاحقاً، أو تحديد "لا يوجد إيصال" إذا لم يؤخذ وصل أمانة على هذا العميل.',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Option 3: No receipt for this customer
            TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: Colors.grey.shade700,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              ),
              onPressed: () => Navigator.of(dialogCtx).pop(
                PromissoryNoteDeliveryResult.noReceipt,
              ),
              icon: const Icon(Icons.do_not_disturb_on_outlined, size: 16),
              label: const Text(
                'لا يوجد إيصال لهذا العميل',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            // Options 1 & 2
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.onSurfaceVariant,
                    side: const BorderSide(color: AppColors.outlineVariant),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () => Navigator.of(dialogCtx).pop(
                    PromissoryNoteDeliveryResult.inSafe,
                  ),
                  child: const Text(
                    'ما زال بالخزينة',
                    style: TextStyle(fontFamily: 'Cairo', fontSize: 13),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () => Navigator.of(dialogCtx).pop(
                    PromissoryNoteDeliveryResult.delivered,
                  ),
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text(
                    'نعم، تم تسليمه',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  );
}
