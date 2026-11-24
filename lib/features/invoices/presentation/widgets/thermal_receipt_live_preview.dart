import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../domain/entities/receipt_config.dart';

class ThermalReceiptLivePreview extends StatelessWidget {
  final ReceiptConfig config;

  const ThermalReceiptLivePreview({
    super.key,
    required this.config,
  });

  @override
  Widget build(BuildContext context) {
    final is58mm = config.paperWidthMm == 58;
    final containerWidth = is58mm ? 270.0 : 330.0;
    final now = DateTime.now();
    final dateFormat = DateFormat('yyyy/MM/dd - hh:mm a');
    final isHospitality = config.storeActivity.contains('مطاعم') ||
        config.storeActivity.contains('كافيه') ||
        config.returnPolicy.contains('الأطعمة والمشروبات');

    return Container(
      width: containerWidth,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Store Header
          Text(
            config.storeName.isNotEmpty ? config.storeName : 'اسم المتجر',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 17,
              color: Colors.black87,
            ),
            textAlign: TextAlign.center,
          ),
          if (config.storeActivity.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              config.storeActivity,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
              textAlign: TextAlign.center,
            ),
          ],
          if (config.storeAddress.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              config.storeAddress,
              style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
          ],
          if (config.storePhone.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              'هاتف: ${config.storePhone}',
              style: TextStyle(fontSize: 10, color: Colors.grey.shade800),
              textAlign: TextAlign.center,
            ),
          ],
          if (config.storePhoneSecondary.isNotEmpty) ...[
            const SizedBox(height: 1),
            Text(
              'هاتف 2: ${config.storePhoneSecondary}',
              style: TextStyle(fontSize: 10, color: Colors.grey.shade800),
              textAlign: TextAlign.center,
            ),
          ],
          if (config.taxNumber.isNotEmpty) ...[
            const SizedBox(height: 1),
            Text(
              'الرقم الضريبي: ${config.taxNumber}',
              style: TextStyle(fontSize: 9, color: Colors.grey.shade700),
              textAlign: TextAlign.center,
            ),
          ],

          if (isHospitality) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.black87, width: 1.5),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Column(
                children: [
                  Text(
                    'طلب رقم: #042',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: Colors.black87,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 2),
                  Text(
                    '[ صالة - طاولة: رقم 4 ]',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 10.5,
                      color: Colors.black87,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 8),
          _dashedLine(),
          const SizedBox(height: 8),

          // Invoice Meta
          _metaRow('رقم الفاتورة:', '#INV-9824', isBold: true),
          const SizedBox(height: 3),
          _metaRow('التاريخ:', dateFormat.format(now)),
          if (config.showCashierName) ...[
            const SizedBox(height: 3),
            _metaRow('الكاشير:', 'أحمد مصطفى'),
          ],
          if (config.showCustomerInfo) ...[
            const SizedBox(height: 3),
            _metaRow('العميل:', 'كريم السيد (01012345678)'),
          ],
          if (config.showPaymentMethod) ...[
            const SizedBox(height: 3),
            _metaRow('طريقة الدفع:', 'نقدي (كاش)'),
          ],

          const SizedBox(height: 8),
          _dashedLine(),
          const SizedBox(height: 8),

          // Table Header
          Row(
            children: const [
              Expanded(
                flex: 5,
                child: Text(
                  'الصنف',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  'ك',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  'السعر',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  'الإجمالي',
                  textAlign: TextAlign.left,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          _dottedLine(),
          const SizedBox(height: 4),

          // Sample Items
          if (isHospitality) ...[
            _sampleItem(
              name: 'وجبة برجر لحم مدخن',
              note: 'بدون بصل - صوص زيادة',
              qty: 1,
              price: '140.00',
              total: '140.00',
            ),
            const SizedBox(height: 4),
            _sampleItem(
              name: 'عصير برتقال فريش',
              note: 'سكر قليل - ثلج زيادة',
              qty: 2,
              price: '40.00',
              total: '80.00',
            ),
          ] else ...[
            _sampleItem(
              name: 'قميص كاجوال رجالي',
              details: config.showItemDetails ? 'كحلي - L' : null,
              qty: 1,
              price: '280.00',
              total: '280.00',
            ),
            const SizedBox(height: 4),
            _sampleItem(
              name: 'بنطلون جينز كلاسيك',
              details: config.showItemDetails ? 'أزرق غامق - 34' : null,
              qty: 1,
              price: '350.00',
              total: '350.00',
            ),
          ],

          const SizedBox(height: 8),
          _dashedLine(),
          const SizedBox(height: 8),

          // Financial Summary
          _summaryRow('المجموع الفرعي:', '630.00 ج.م'),
          const SizedBox(height: 2),
          _summaryRow('خصم:', '-30.00 ج.م', isDiscount: true),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: const [
                Expanded(
                  child: Text(
                    'الإجمالي المطلوب:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
                Text(
                  '600.00 ج.م',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ],
            ),
          ),

          // Barcode Simulation
          if (config.showBarcode) ...[
            const SizedBox(height: 12),
            Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  36,
                  (index) => Container(
                    width: (index % 4 == 0) ? 3 : ((index % 3 == 0) ? 2 : 1),
                    margin: const EdgeInsets.symmetric(horizontal: 1.2),
                    color: (index % 5 == 1) ? Colors.transparent : Colors.black87,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 2),
            const Text(
              '#INV-9824',
              style: TextStyle(fontSize: 10, letterSpacing: 1),
            ),
          ],

          const SizedBox(height: 10),
          _dashedLine(),
          const SizedBox(height: 8),

          // Footer Policy & Greeting
          if (config.returnPolicy.isNotEmpty) ...[
            Text(
              config.returnPolicy,
              style: TextStyle(fontSize: 9.5, color: Colors.grey.shade700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
          ],
          if (config.footerGreeting.isNotEmpty) ...[
            Text(
              config.footerGreeting,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10.5),
              textAlign: TextAlign.center,
            ),
          ],
          if (isHospitality && config.wifiInfo.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              config.wifiInfo,
              style: TextStyle(fontSize: 9, color: Colors.grey.shade700),
              textAlign: TextAlign.center,
            ),
          ],
          if (isHospitality && config.storePhone.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              'خدمة التوصيل والطلبات: ${config.storePhone}',
              style: TextStyle(fontSize: 8.5, color: Colors.grey.shade700),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 4),
          Text(
            '[ مقاس الورق: ${config.paperWidthMm} مم ]',
            style: TextStyle(fontSize: 8, color: Colors.grey.shade400),
          ),
        ],
      ),
    );
  }

  Widget _metaRow(String label, String value, {bool isBold = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            color: Colors.grey.shade700,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.left,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              color: Colors.black87,
            ),
          ),
        ),
      ],
    );
  }

  Widget _summaryRow(String label, String value, {bool isDiscount = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: isDiscount ? Colors.red.shade700 : Colors.black87,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.left,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isDiscount ? Colors.red.shade700 : Colors.black87,
            ),
          ),
        ),
      ],
    );
  }

  Widget _sampleItem({
    required String name,
    String? details,
    String? note,
    required int qty,
    required String price,
    required String total,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          details != null ? '$name ($details)' : name,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 10.5),
        ),
        if (note != null && note.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(top: 1, bottom: 2, right: 4),
            child: Text(
              '* ملاحظة التحضير: ($note)',
              style: TextStyle(
                fontSize: 9,
                color: Colors.grey.shade700,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
        Row(
          children: [
            const Expanded(flex: 5, child: SizedBox()),
            Expanded(
              flex: 2,
              child: Text(
                '$qty',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 10.5),
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                price,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 10.5),
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                total,
                textAlign: TextAlign.left,
                style: const TextStyle(fontSize: 10.5),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _dashedLine() {
    return Text(
      '------------------------------------------------',
      style: TextStyle(fontSize: 9, color: Colors.grey.shade400),
      maxLines: 1,
      overflow: TextOverflow.clip,
    );
  }

  Widget _dottedLine() {
    return Text(
      '- - - - - - - - - - - - - - - - - - - - - - - -',
      style: TextStyle(fontSize: 9, color: Colors.grey.shade400),
      maxLines: 1,
      overflow: TextOverflow.clip,
    );
  }
}
