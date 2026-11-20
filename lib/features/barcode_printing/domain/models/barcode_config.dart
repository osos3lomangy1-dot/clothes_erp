import 'dart:convert';
import 'package:equatable/equatable.dart';
import 'barcode_label_item.dart';

class BarcodeConfig extends Equatable {
  final BarcodeLabelSize selectedSize;
  final String storeName;
  final bool showStoreName;
  final bool showProductName;
  final bool showColorAndSize;
  final bool showPrice;
  final bool showBarcodeText;
  final int defaultCopies;

  const BarcodeConfig({
    this.selectedSize = BarcodeLabelSize.roll50x30,
    this.storeName = 'أوركيد للملابس',
    this.showStoreName = true,
    this.showProductName = true,
    this.showColorAndSize = true,
    this.showPrice = true,
    this.showBarcodeText = true,
    this.defaultCopies = 1,
  });

  factory BarcodeConfig.defaults() => const BarcodeConfig();

  BarcodeConfig copyWith({
    BarcodeLabelSize? selectedSize,
    String? storeName,
    bool? showStoreName,
    bool? showProductName,
    bool? showColorAndSize,
    bool? showPrice,
    bool? showBarcodeText,
    int? defaultCopies,
  }) {
    return BarcodeConfig(
      selectedSize: selectedSize ?? this.selectedSize,
      storeName: storeName ?? this.storeName,
      showStoreName: showStoreName ?? this.showStoreName,
      showProductName: showProductName ?? this.showProductName,
      showColorAndSize: showColorAndSize ?? this.showColorAndSize,
      showPrice: showPrice ?? this.showPrice,
      showBarcodeText: showBarcodeText ?? this.showBarcodeText,
      defaultCopies: defaultCopies ?? this.defaultCopies,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'selectedSize': selectedSize.name,
      'storeName': storeName,
      'showStoreName': showStoreName,
      'showProductName': showProductName,
      'showColorAndSize': showColorAndSize,
      'showPrice': showPrice,
      'showBarcodeText': showBarcodeText,
      'defaultCopies': defaultCopies,
    };
  }

  factory BarcodeConfig.fromMap(Map<String, dynamic> map) {
    final sizeName = map['selectedSize'] as String? ?? 'roll50x30';
    final size = BarcodeLabelSize.values.firstWhere(
      (s) => s.name == sizeName || s.toString().split('.').last == sizeName,
      orElse: () => BarcodeLabelSize.roll50x30,
    );

    return BarcodeConfig(
      selectedSize: size,
      storeName: map['storeName'] as String? ?? 'أوركيد للملابس',
      showStoreName: map['showStoreName'] as bool? ?? true,
      showProductName: map['showProductName'] as bool? ?? true,
      showColorAndSize: map['showColorAndSize'] as bool? ?? true,
      showPrice: map['showPrice'] as bool? ?? true,
      showBarcodeText: map['showBarcodeText'] as bool? ?? true,
      defaultCopies: (map['defaultCopies'] as num?)?.toInt() ?? 1,
    );
  }

  String toJson() => json.encode(toMap());

  factory BarcodeConfig.fromJson(String source) =>
      BarcodeConfig.fromMap(json.decode(source) as Map<String, dynamic>);

  @override
  List<Object?> get props => [
        selectedSize,
        storeName,
        showStoreName,
        showProductName,
        showColorAndSize,
        showPrice,
        showBarcodeText,
        defaultCopies,
      ];
}

