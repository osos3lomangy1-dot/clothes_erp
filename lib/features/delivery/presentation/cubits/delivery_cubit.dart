import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/branch_provider.dart';
import '../../domain/entities/delivery_courier_entity.dart';
import '../../domain/entities/delivery_order_entity.dart';
import '../../domain/repositories/delivery_repository.dart';
import 'delivery_state.dart';

@injectable
class DeliveryCubit extends Cubit<DeliveryState> {
  final DeliveryRepository _repo;
  final BranchProvider _branchProvider;

  DeliveryCubit(this._repo, this._branchProvider) : super(const DeliveryState()) {
    init();
  }

  Future<void> init() async {
    await Future.wait([
      loadOrders(),
      loadCouriers(),
    ]);
  }

  Future<void> loadOrders() async {
    emit(state.copyWith(status: DeliveryStatus.loading));
    final res = await _repo.getDeliveryOrders(
      status: state.statusFilter == 'all' ? null : state.statusFilter,
      courierId: state.selectedCourierId,
    );
    res.fold(
      (failure) => emit(state.copyWith(
        status: DeliveryStatus.error,
        errorMessage: failure.message,
      )),
      (orders) => emit(state.copyWith(
        status: DeliveryStatus.success,
        orders: orders,
      )),
    );
  }

  Future<void> loadCouriers() async {
    final res = await _repo.getCouriers();
    res.fold(
      (_) => null,
      (couriers) => emit(state.copyWith(couriers: couriers)),
    );
  }

  void setStatusFilter(String filter) {
    emit(state.copyWith(statusFilter: filter));
    loadOrders();
  }

  void setSearchQuery(String query) {
    emit(state.copyWith(searchQuery: query));
  }

  Future<bool> createDeliveryOrder(DeliveryOrderEntity order) async {
    final res = await _repo.createDeliveryOrder(order);
    return res.fold(
      (failure) {
        emit(state.copyWith(
          status: DeliveryStatus.error,
          errorMessage: failure.message,
        ));
        return false;
      },
      (_) {
        loadOrders();
        return true;
      },
    );
  }

  Future<void> updateDeliveryStatus(String orderId, String newStatus) async {
    final deliveredAt = newStatus == 'delivered' ? DateTime.now() : null;
    final res = await _repo.updateDeliveryStatus(
      orderId,
      newStatus,
      deliveredAt: deliveredAt,
    );
    res.fold(
      (failure) => emit(state.copyWith(
        status: DeliveryStatus.error,
        errorMessage: failure.message,
      )),
      (_) => loadOrders(),
    );
  }

  Future<void> assignCourier(
    String orderId,
    String courierId,
    String courierName,
  ) async {
    final res = await _repo.assignCourier(orderId, courierId, courierName);
    res.fold(
      (failure) => emit(state.copyWith(
        status: DeliveryStatus.error,
        errorMessage: failure.message,
      )),
      (_) => loadOrders(),
    );
  }

  Future<bool> addCourier({
    required String name,
    required String phone,
    String? vehicleType,
  }) async {
    final branchId = await _branchProvider.getBranchId();
    final courier = DeliveryCourierEntity(
      id: const Uuid().v4(),
      branchId: branchId,
      name: name.trim(),
      phone: phone.trim(),
      vehicleType: vehicleType,
      createdAt: DateTime.now(),
    );

    final res = await _repo.addCourier(courier);
    return res.fold(
      (failure) => false,
      (_) {
        loadCouriers();
        return true;
      },
    );
  }

  Future<void> loadCourierSettlement(String courierId) async {
    final res = await _repo.getCourierSettlement(courierId);
    res.fold(
      (_) => null,
      (summary) => emit(state.copyWith(settlementSummary: summary)),
    );
  }

  Future<bool> settleCourierOrders(
    String courierId,
    List<String> orderIds,
  ) async {
    final res = await _repo.settleCourierOrders(courierId, orderIds);
    return res.fold(
      (failure) => false,
      (_) {
        loadOrders();
        loadCourierSettlement(courierId);
        return true;
      },
    );
  }
}

