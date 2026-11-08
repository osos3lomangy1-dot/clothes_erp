import 'package:equatable/equatable.dart';

enum VariantFormStatus { initial, loading, success, error }

class VariantFormState extends Equatable {
  final String productCode;
  final String color;
  final String size;
  final int quantity;
  final int costPrice;
  final int salePrice;
  final int wholesalePrice;
  final int minStock;
  final VariantFormStatus status;
  final String? errorMessage;
  final bool isEdit;

  const VariantFormState({
    this.productCode = '',
    this.color = '',
    this.size = '',
    this.quantity = 0,
    this.costPrice = 0,
    this.salePrice = 0,
    this.wholesalePrice = 0,
    this.minStock = 0,
    this.status = VariantFormStatus.initial,
    this.errorMessage,
    this.isEdit = false,
  });

  VariantFormState copyWith({
    String? productCode,
    String? color,
    String? size,
    int? quantity,
    int? costPrice,
    int? salePrice,
    int? wholesalePrice,
    int? minStock,
    VariantFormStatus? status,
    String? errorMessage,
    bool? isEdit,
  }) {
    return VariantFormState(
      productCode: productCode ?? this.productCode,
      color: color ?? this.color,
      size: size ?? this.size,
      quantity: quantity ?? this.quantity,
      costPrice: costPrice ?? this.costPrice,
      salePrice: salePrice ?? this.salePrice,
      wholesalePrice: wholesalePrice ?? this.wholesalePrice,
      minStock: minStock ?? this.minStock,
      status: status ?? this.status,
      errorMessage: errorMessage,
      isEdit: isEdit ?? this.isEdit,
    );
  }

  @override
  List<Object?> get props => [
        productCode,
        color,
        size,
        quantity,
        costPrice,
        salePrice,
        wholesalePrice,
        minStock,
        status,
        errorMessage,
        isEdit,
      ];
}
