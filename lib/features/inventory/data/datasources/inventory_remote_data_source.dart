import 'package:injectable/injectable.dart';
import '../../../product_variants/data/models/variant_model.dart';

abstract class InventoryRemoteDataSource {
  Future<List<VariantModel>> getAllInventory();
  Future<List<VariantModel>> getLowStockInventory();
}

@LazySingleton(as: InventoryRemoteDataSource)
class InventoryRemoteDataSourceImpl implements InventoryRemoteDataSource {
  InventoryRemoteDataSourceImpl();

  @override
  Future<List<VariantModel>> getAllInventory() async => [];

  @override
  Future<List<VariantModel>> getLowStockInventory() async => [];
}
