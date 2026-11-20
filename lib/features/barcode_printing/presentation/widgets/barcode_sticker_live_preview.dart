import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/money.dart';
import '../../domain/models/barcode_config.dart';
import '../../domain/models/barcode_label_item.dart';

class BarcodeStickerLivePreview extends StatelessWidget {
  final BarcodeConfig config;
  final BarcodeLabelItem sampleItem;

  const BarcodeStickerLivePreview({
    super.key,
    required this.config,
    required this.sampleItem,
  });

  @override
  Widget build(BuildContext context) {
    final size = config.selectedSize;
    final isA4 = size == BarcodeLabelSize.sheetA4;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9), // Calm neutral slate grey background
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header Badge
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.visibility_rounded, size: 14, color: AppColors.primary),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          'معاينة الاستيكر',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isA4 ? Icons.grid_view_rounded : Icons.label_outline_rounded,
                      size: 13,
                      color: Colors.grey.shade700,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isA4
                          ? 'A4'
                          : '${size.widthMm.toInt()}×${size.heightMm.toInt()}مم',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Center Preview Area
          Center(
            child: isA4 ? _buildA4MiniSheetPreview() : _buildSingleStickerCard(),
          ),
          const SizedBox(height: 14),

          // Note underneath
          Text(
            isA4
                ? 'يتم توزيع الملصقات بنظام 24 ملصق بالصفحة (3 أعمدة × 8 صفوف) على الورق العادي A4'
                : 'الاستيكر الفعلي يطبع مباشرة على بكر طابعات الباركود الحرارية (Xprinter / Zebra / Rongta)',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSingleStickerCard() {
    final size = config.selectedSize;
    // Calculate aspect ratio: width / height
    final double aspectRatio = size.widthMm / size.heightMm;

    // Display width bounds
    const double maxStickerWidth = 280;
    final double calculatedHeight = maxStickerWidth / aspectRatio;

    return Container(
      width: maxStickerWidth,
      height: calculatedHeight.clamp(140.0, 220.0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8), // Thermal die-cut rounded corners
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
        border: Border.all(color: Colors.grey.shade300, width: 1),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Store Name
          if (config.showStoreName && config.storeName.trim().isNotEmpty) ...[
            Text(
              config.storeName.trim(),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E293B),
                letterSpacing: 0.2,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ] else
            const SizedBox(height: 2),

          // Product Name
          if (config.showProductName) ...[
            Text(
              sampleItem.productName,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],

          // Color & Size Chip
          if (config.showColorAndSize &&
              (sampleItem.color.isNotEmpty || sampleItem.size.isNotEmpty)) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                [
                  if (sampleItem.color.isNotEmpty) sampleItem.color,
                  if (sampleItem.size.isNotEmpty) 'مقاس ${sampleItem.size}',
                ].join(' • '),
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF334155),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],

          // Vector Barcode Lines
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: CustomPaint(
                painter: _VectorBarcodePainter(
                  sku: sampleItem.sku.isNotEmpty ? sampleItem.sku : '100010001000',
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),

          // Barcode Text (SKU)
          if (config.showBarcodeText) ...[
            Text(
              sampleItem.sku.isNotEmpty ? sampleItem.sku : '100010001000',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
                color: Color(0xFF1E293B),
              ),
              maxLines: 1,
              textAlign: TextAlign.center,
            ),
          ],

          // Price Tag
          if (config.showPrice) ...[
            const SizedBox(height: 2),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${Money(sampleItem.salePricePiasters).toDisplay()} ج.م',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: AppColors.primary,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildA4MiniSheetPreview() {
    return Container(
      width: 280,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        children: [
          Text(
            'شبكة ورق A4 (3 × 8 ملصقات)',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 8),
          // 3 columns x 4 visible rows mini preview
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 12,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 6,
              mainAxisSpacing: 6,
              childAspectRatio: 1.7,
            ),
            itemBuilder: (ctx, idx) {
              return Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.grey.shade300, width: 0.5),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      sampleItem.productName,
                      style: const TextStyle(fontSize: 7, fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Expanded(
                      child: CustomPaint(
                        painter: _VectorBarcodePainter(sku: sampleItem.sku),
                        child: const SizedBox.expand(),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${Money(sampleItem.salePricePiasters).toDisplay()} ج.م',
                      style: TextStyle(
                        fontSize: 7,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Dynamic Custom Painter drawing realistic Code 128 vertical barcode bars
class _VectorBarcodePainter extends CustomPainter {
  final String sku;

  const _VectorBarcodePainter({required this.sku});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final paint = Paint()
      ..color = Colors.black
      ..isAntiAlias = false
      ..style = PaintingStyle.fill;

    // Generate consistent bar widths from the SKU string
    final seed = sku.isEmpty ? '123456789' : sku;
    final List<int> pattern = [];

    // Quiet zone left
    pattern.addAll([0, 0, 0]);

    // Start pattern: thick-thin-thick
    pattern.addAll([2, 1, 1, 2, 1, 1]);

    for (int i = 0; i < seed.length; i++) {
      final code = seed.codeUnitAt(i);
      final w1 = (code % 3) + 1;
      final s1 = ((code >> 1) % 2) + 1;
      final w2 = ((code >> 2) % 3) + 1;
      final s2 = ((code >> 3) % 2) + 1;
      pattern.addAll([w1, s1, w2, s2]);
    }

    // Stop pattern: thick-thin-thick-thick
    pattern.addAll([2, 1, 2, 2, 1, 1, 2]);

    // Quiet zone right
    pattern.addAll([0, 0, 0]);

    final totalUnits = pattern.fold<int>(0, (sum, val) => sum + (val == 0 ? 1 : val));
    if (totalUnits == 0) return;

    final double unitWidth = size.width / totalUnits;
    double currentX = 0;
    bool isBar = false;

    for (final widthUnits in pattern) {
      final actualUnits = widthUnits == 0 ? 1 : widthUnits;
      final double widthPx = actualUnits * unitWidth;

      if (widthUnits > 0 && isBar) {
        canvas.drawRect(
          Rect.fromLTWH(currentX, 0, widthPx, size.height),
          paint,
        );
      }
      currentX += widthPx;
      if (widthUnits > 0) {
        isBar = !isBar;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _VectorBarcodePainter oldDelegate) {
    return oldDelegate.sku != sku;
  }
}
