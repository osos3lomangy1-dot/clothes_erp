import 'package:equatable/equatable.dart';
import '../../domain/entities/pre_order_batch_entity.dart';
import '../../domain/entities/pre_order_entity.dart';

enum PreOrdersViewStatus { initial, loading, loaded, error }

class PreOrdersState extends Equatable {
  final PreOrdersViewStatus status;
  final List<PreOrderEntity> allOrders;
  final List<PreOrderBatchEntity> allBatches;
  final String activeMode; // 'orders' أو 'batches'
  final String selectedTab;
  final String searchQuery;
  final String? errorMessage;
  final bool isSubmitting;

  const PreOrdersState({
    this.status = PreOrdersViewStatus.initial,
    this.allOrders = const [],
    this.allBatches = const [],
    this.activeMode = 'orders',
    this.selectedTab = 'all',
    this.searchQuery = '',
    this.errorMessage,
    this.isSubmitting = false,
  });

  int get totalCount => allOrders.length;
  int get batchesCount => allBatches.length;

  int get pendingCount => allOrders
      .where((o) => o.status == PreOrderStatuses.pendingProcessing)
      .length;

  int get arrivedCount => allOrders
      .where((o) => o.status == PreOrderStatuses.arrivedAtStore)
      .length;

  int get deliveredCount =>
      allOrders.where((o) => o.status == PreOrderStatuses.delivered).length;

  int get defaultedCount => allOrders
      .where((o) => o.status == PreOrderStatuses.defaultedForfeited)
      .length;

  int get refundedCount => allOrders
      .where((o) => o.status == PreOrderStatuses.refundedCancelled)
      .length;

  int get pendingBatchesCount => allBatches
      .where((b) => b.status == PreOrderStatuses.pendingProcessing)
      .length;

  int get arrivedBatchesCount => allBatches
      .where((b) => b.status == PreOrderStatuses.arrivedAtStore)
      .length;

  List<PreOrderEntity> get filteredOrders {
    var list = allOrders;
    if (selectedTab != 'all') {
      list = list.where((o) => o.status == selectedTab).toList();
    }
    if (searchQuery.trim().isNotEmpty) {
      final q = searchQuery.trim().toLowerCase();
      list = list.where((o) {
        return o.orderNumber.toLowerCase().contains(q) ||
            o.customerName.toLowerCase().contains(q) ||
            o.customerPhone.contains(q) ||
            (o.agentName?.toLowerCase().contains(q) ?? false) ||
            (o.trackingNumber?.toLowerCase().contains(q) ?? false) ||
            (o.notes?.toLowerCase().contains(q) ?? false);
      }).toList();
    }
    return list;
  }

  List<PreOrderBatchEntity> get filteredBatches {
    var list = allBatches;
    if (selectedTab != 'all') {
      list = list.where((b) => b.status == selectedTab).toList();
    }
    if (searchQuery.trim().isNotEmpty) {
      final q = searchQuery.trim().toLowerCase();
      list = list.where((b) {
        return b.batchNumber.toLowerCase().contains(q) ||
            (b.agentName?.toLowerCase().contains(q) ?? false) ||
            (b.trackingNumber?.toLowerCase().contains(q) ?? false);
      }).toList();
    }
    return list;
  }

  PreOrdersState copyWith({
    PreOrdersViewStatus? status,
    List<PreOrderEntity>? allOrders,
    List<PreOrderBatchEntity>? allBatches,
    String? activeMode,
    String? selectedTab,
    String? searchQuery,
    String? errorMessage,
    bool? isSubmitting,
  }) {
    return PreOrdersState(
      status: status ?? this.status,
      allOrders: allOrders ?? this.allOrders,
      allBatches: allBatches ?? this.allBatches,
      activeMode: activeMode ?? this.activeMode,
      selectedTab: selectedTab ?? this.selectedTab,
      searchQuery: searchQuery ?? this.searchQuery,
      errorMessage: errorMessage,
      isSubmitting: isSubmitting ?? this.isSubmitting,
    );
  }

  @override
  List<Object?> get props => [
    status,
    allOrders,
    allBatches,
    activeMode,
    selectedTab,
    searchQuery,
    errorMessage,
    isSubmitting,
  ];
}
