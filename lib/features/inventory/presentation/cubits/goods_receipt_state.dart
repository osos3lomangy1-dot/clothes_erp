import 'package:equatable/equatable.dart';
import '../../domain/entities/goods_receipt_entity.dart';

enum GoodsReceiptStatus { initial, loading, loaded, success, error }

class GoodsReceiptState extends Equatable {
  final GoodsReceiptStatus status;
  final List<GoodsReceiptEntity> receipts;
  final String? errorMessage;
  final String? successMessage;

  const GoodsReceiptState({
    this.status = GoodsReceiptStatus.initial,
    this.receipts = const [],
    this.errorMessage,
    this.successMessage,
  });

  GoodsReceiptState copyWith({
    GoodsReceiptStatus? status,
    List<GoodsReceiptEntity>? receipts,
    String? errorMessage,
    String? successMessage,
  }) {
    return GoodsReceiptState(
      status: status ?? this.status,
      receipts: receipts ?? this.receipts,
      errorMessage: errorMessage,
      successMessage: successMessage,
    );
  }

  @override
  List<Object?> get props => [status, receipts, errorMessage, successMessage];
}

