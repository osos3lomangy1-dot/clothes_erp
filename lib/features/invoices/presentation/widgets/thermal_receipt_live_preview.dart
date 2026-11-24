import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../domain/entities/receipt_config.dart';

class ThermalReceiptLivePreview extends StatelessWidget {
  final ReceiptConfig config;

  const ThermalReceiptLivePreview({super.key, required this.config});

  @override
  Widget build(BuildContext context) {
    final is58mm = config.paperWidthMm == 58;
    final containerWidth = is58mm ? 270.0 : 330.0;
    final now = DateTime.now();
    final dateFormat = DateFormat('yyyy/MM/dd - hh:mm a');
    final isHospitality =
        config.storeActivity.contains('مطاعم') ||
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

          // Table Header (2-Tier Layout)
          Row(
            children: const [
              Expanded(
                flex: 4,
                child: Text(
                  'الصنف',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 9.5),
                ),
              ),
              Expanded(
                flex: 6,
                child: Text(
                  'الكمية × السعر / الإجمالي',
                  textAlign: TextAlign.left,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 9.5),
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

          const SizedBox(height: 6),
          _dashedLine(),
          const SizedBox(height: 4),

          // Total items and pieces (Addendum 30.7)
          const Text(
            'عدد الأصناف: 2  |  إجمالي القطع: 3',
            style: TextStyle(fontSize: 10, color: Colors.black87),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          _dashedLine(),
          const SizedBox(height: 6),

          // Financial Summary
          _summaryRow('المجموع الفرعي:', '630.00 ج.م'),
          const SizedBox(height: 2),
          _summaryRow('خصم:', '-30.00 ج.م', isDiscount: true),
          if (isHospitality && config.dineInServiceChargeEnabled) ...[
            const SizedBox(height: 2),
            _summaryRow('خدمة صالة (${config.dineInServiceChargeRate}%):', '+72.00 ج.م'),
          ],
          if (config.taxEnabled) ...[
            const SizedBox(height: 2),
            if (config.taxInclusive)
              Text(
                '* الأسعار شاملة ضريبة القيمة المضافة ${config.taxRate}%',
                style: const TextStyle(fontSize: 8.5, color: Colors.grey),
              )
            else
              _summaryRow('ضريبة القيمة المضافة (${config.taxRate}%):', '+84.00 ج.م'),
          ],
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
          const SizedBox(height: 4),
          _summaryRow('المبلغ المدفوع (نقداً):', '650.00 ج.م'),
          const SizedBox(height: 2),
          _summaryRow('الباقي المسترد للعميل:', '50.00 ج.م'),

          // Barcode Simulation (QR Code - Addendum 30.7)
          if (config.showBarcode) ...[
            const SizedBox(height: 10),
            Center(
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.black87, width: 1.5),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Center(
                  child: Icon(Icons.qr_code_2_rounded, size: 40, color: Colors.black87),
                ),
              ),
            ),
            const SizedBox(height: 3),
            const Text(
              '#INV-9824',
              style: TextStyle(fontSize: 9.5, letterSpacing: 0.5, color: Colors.grey),
              textAlign: TextAlign.center,
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
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 10.5,
              ),
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
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 9.5,
            color: Colors.grey.shade700,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.left,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            style: TextStyle(
              fontSize: 9.5,
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
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            style: TextStyle(
              fontSize: 9.5,
              color: isDiscount ? Colors.red.shade700 : Colors.black87,
            ),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          value,
          textAlign: TextAlign.left,
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w600,
            color: isDiscount ? Colors.red.shade700 : Colors.black87,
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
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
        ),
        if (note != null && note.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(top: 1, bottom: 2, right: 4),
            child: Text(
              '* ملاحظة التحضير: ($note)',
              style: TextStyle(
                fontSize: 9.5,
                color: Colors.grey.shade700,
              ),
            ),
          ),
        ],
        const SizedBox(height: 2),
        Row(
          children: [
            Expanded(
              child: Text(
                '$qty × $price ج.م',
                style: TextStyle(fontSize: 9.5, color: Colors.grey.shade800),
              ),
            ),
            Text(
              '$total ج.م',
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ],
    );
  }

  Widget _dashedLine() {
    return const Divider(
      height: 1,
      thickness: 0.8,
      color: Color(0xFFBDBDBD),
    );
  }

  Widget _dottedLine() {
    return const Divider(
      height: 1,
      thickness: 0.8,
      color: Color(0xFFE0E0E0),
    );
  }
}
