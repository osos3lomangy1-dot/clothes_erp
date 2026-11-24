import 'package:equatable/equatable.dart';
import 'invoice_item_details_entity.dart';

typedef InvoiceEntity = InvoiceDetailsEntity;

class InvoiceDetailsEntity extends Equatable {
  final String id;
  final String shortRef;
  final DateTime date;
  final String cashierId;
  final String cashierName;
  final String? customerId;
  final String? customerName;
  final String? customerPhone;
  final int subtotal; // in piasters
  final int discountAmount; // in piasters
  final int total; // in piasters
  final String paymentMethod;
  final String? shiftId;
  final String status;
  final List<InvoiceItemDetailsEntity> items;
  final String? orderType; // 'dineIn', 'takeaway', 'delivery'
  final String? tableNumber;
  final String? orderNumber;
  final String? wifiInfo;

  const InvoiceDetailsEntity({
    required this.id,
    required this.shortRef,
    required this.date,
    required this.cashierId,
    this.cashierName = '',
    this.customerId,
    this.customerName,
    this.customerPhone,
    required this.subtotal,
    this.discountAmount = 0,
    required this.total,
    required this.paymentMethod,
    this.shiftId,
    this.status = 'completed',
    required this.items,
    this.orderType,
    this.tableNumber,
    this.orderNumber,
    this.wifiInfo,
  });

  InvoiceDetailsEntity copyWith({
    String? id,
    String? shortRef,
    DateTime? date,
    String? cashierId,
    String? cashierName,
    String? customerId,
    String? customerName,
    String? customerPhone,
    int? subtotal,
    int? discountAmount,
    int? total,
    String? paymentMethod,
    String? shiftId,
    String? status,
    List<InvoiceItemDetailsEntity>? items,
    String? orderType,
    String? tableNumber,
    String? orderNumber,
    String? wifiInfo,
  }) {
    return InvoiceDetailsEntity(
      id: id ?? this.id,
      shortRef: shortRef ?? this.shortRef,
      date: date ?? this.date,
      cashierId: cashierId ?? this.cashierId,
      cashierName: cashierName ?? this.cashierName,
      customerId: customerId ?? this.customerId,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      subtotal: subtotal ?? this.subtotal,
      discountAmount: discountAmount ?? this.discountAmount,
      total: total ?? this.total,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      shiftId: shiftId ?? this.shiftId,
      status: status ?? this.status,
      items: items ?? this.items,
      orderType: orderType ?? this.orderType,
      tableNumber: tableNumber ?? this.tableNumber,
      orderNumber: orderNumber ?? this.orderNumber,
      wifiInfo: wifiInfo ?? this.wifiInfo,
    );
  }

  int get totalItemsCount => items.fold<int>(0, (sum, i) => sum + i.qty);
  int get totalPromotionDiscount =>
      items.fold<int>(0, (sum, i) => sum + i.promotionDiscount);
  int get totalProfitPiasters =>
      items.fold<int>(0, (sum, i) => sum + i.profitPiasters);
  double get totalProfitMarginPercent =>
      total > 0 ? (totalProfitPiasters / total) * 100 : 0.0;

  @override
  List<Object?> get props => [
        id,
        shortRef,
        date,
        cashierId,
        cashierName,
        customerId,
        customerName,
        customerPhone,
        subtotal,
        discountAmount,
        total,
        paymentMethod,
        shiftId,
        status,
        items,
        orderType,
        tableNumber,
        orderNumber,
        wifiInfo,
      ];
}

