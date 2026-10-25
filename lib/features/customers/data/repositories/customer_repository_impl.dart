import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/errors/failures.dart';
import 'package:dartz/dartz.dart';
import '../../domain/entities/customer_entity.dart';
import '../../domain/repositories/customer_repository.dart';
import '../../data/models/customer_model.dart';

@LazySingleton(as: CustomerRepository)
class CustomerRepositoryImpl implements CustomerRepository {
  final FirebaseFirestore _firestore;

  CustomerRepositoryImpl(this._firestore);

  @override
  Future<Either<Failure, List<CustomerEntity>>> getCustomers() async {
    try {
      final snapshot = await _firestore.collection('customers').get();
      final customers = snapshot.docs
          .map((doc) => CustomerModel.fromFirestore(doc.data(), doc.id))
          .toList();
      return Right(customers);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> addCustomer(CustomerEntity customer) async {
    try {
      await _firestore.collection('customers').add(
            CustomerModel(
              id: customer.id,
              name: customer.name,
              phone: customer.phone,
              loyaltyPoints: customer.loyaltyPoints,
              createdAt: customer.createdAt,
            ).toFirestore(),
          );
      return const Right(null);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> updateCustomer(CustomerEntity customer) async {
    try {
      await _firestore.collection('customers').doc(customer.id).update(
            CustomerModel(
              id: customer.id,
              name: customer.name,
              phone: customer.phone,
              loyaltyPoints: customer.loyaltyPoints,
              createdAt: customer.createdAt,
            ).toFirestore(),
          );
      return const Right(null);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }
}
