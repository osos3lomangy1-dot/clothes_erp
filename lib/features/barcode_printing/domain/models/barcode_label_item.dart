import 'package:equatable/equatable.dart';

enum BarcodeLabelSize {
  roll50x30(name: 'بكرة حرارية 50 × 30 مم (الأكثر شيوعاً)', widthMm: 50, heightMm: 30),
  roll38x25(name: 'بكرة حرارية 38 × 25 مم (صغيرة)', widthMm: 38, heightMm: 25),
  sheetA4(name: 'ورق عادي A4 (شبكة ملصقات)', widthMm: 210, heightMm: 297);

  final String name;
  final double widthMm;
  final double heightMm;

  const BarcodeLabelSize({
    required this.name,
    required this.widthMm,
    required this.heightMm,
  });
}

class BarcodeLabelItem extends Equatable {
  final String variantId;
  final String productName;
  final String sku;
  final String color;
  final String size;
  final int salePricePiasters;
  final int copies;

  const BarcodeLabelItem({
    required this.variantId,
    required this.productName,
    required this.sku,
    required this.color,
    required this.size,
    required this.salePricePiasters,
    this.copies = 1,
  });

  BarcodeLabelItem copyWith({
    String? variantId,
    String? productName,
    String? sku,
    String? color,
    String? size,
    int? salePricePiasters,
    int? copies,
  }) {
    return BarcodeLabelItem(
      variantId: variantId ?? this.variantId,
      productName: productName ?? this.productName,
      sku: sku ?? this.sku,
      color: color ?? this.color,
      size: size ?? this.size,
      salePricePiasters: salePricePiasters ?? this.salePricePiasters,
      copies: copies ?? this.copies,
    );
  }

  @override
  List<Object?> get props => [
        variantId,
        productName,
        sku,
        color,
        size,
        salePricePiasters,
        copies,
      ];
}

