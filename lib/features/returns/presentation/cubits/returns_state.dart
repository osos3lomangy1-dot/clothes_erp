import 'package:equatable/equatable.dart';
import '../../../pos/domain/entities/sale_entity.dart';
import '../../domain/entities/return_entity.dart';
import '../../domain/entities/return_item_entity.dart';

class ReturnsState extends Equatable {
  final List<SaleEntity> recentSales;
  final List<ReturnEntity> returnsHistory;
  final SaleEntity? selectedSale;
  final List<ReturnItemEntity> returnItems;
  final bool isLoading;
  final bool isProcessing;
  final String? errorMessage;
  final String? successMessage;

  const ReturnsState({
    this.recentSales = const [],
    this.returnsHistory = const [],
    this.selectedSale,
    this.returnItems = const [],
    this.isLoading = false,
    this.isProcessing = false,
    this.errorMessage,
    this.successMessage,
  });

  int get totalRefund => returnItems.fold<int>(0, (sum, i) => sum + i.lineTotal);

  ReturnsState copyWith({
    List<SaleEntity>? recentSales,
    List<ReturnEntity>? returnsHistory,
    SaleEntity? selectedSale,
    bool clearSelectedSale = false,
    List<ReturnItemEntity>? returnItems,
    bool? isLoading,
    bool? isProcessing,
    String? errorMessage,
    String? successMessage,
    bool clearMessages = false,
  }) {
    return ReturnsState(
      recentSales: recentSales ?? this.recentSales,
      returnsHistory: returnsHistory ?? this.returnsHistory,
      selectedSale: clearSelectedSale ? null : (selectedSale ?? this.selectedSale),
      returnItems: returnItems ?? this.returnItems,
      isLoading: isLoading ?? this.isLoading,
      isProcessing: isProcessing ?? this.isProcessing,
      errorMessage: clearMessages ? null : (errorMessage ?? this.errorMessage),
      successMessage: clearMessages ? null : (successMessage ?? this.successMessage),
    );
  }

  @override
  List<Object?> get props => [
        recentSales,
        returnsHistory,
        selectedSale,
        returnItems,
        isLoading,
        isProcessing,
        errorMessage,
        successMessage,
      ];
}
