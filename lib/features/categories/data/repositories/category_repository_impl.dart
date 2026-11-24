import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/constants/retail_sector.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/features/feature_gate.dart';
import '../../../products/domain/entities/activity_type.dart';
import '../../../settings/data/services/activity_settings_service.dart';
import '../../domain/entities/category_entity.dart';
import '../../domain/repositories/category_repository.dart';
import '../datasources/category_local_data_source.dart';

@LazySingleton(as: CategoryRepository)
class CategoryRepositoryImpl implements CategoryRepository {
  final CategoryLocalDataSource _localDataSource;

  static const List<String> defaultHospitalityCategories = [
    'وجبات وساندوتشات',
    'مشروبات وعصائر',
    'بيتزا وفطائر',
    'مقبلات وإضافات',
    'حلويات ومخبوزات',
  ];

  CategoryRepositoryImpl(this._localDataSource);

  Future<bool> _isHospitalityActive() async {
    String sectorMode = RetailSector.apparel;
    if (getIt.isRegistered<FeatureGate>()) {
      try {
        sectorMode =
            await getIt<FeatureGate>().getMeta(RetailSector.metaKey) ??
                RetailSector.apparel;
      } catch (_) {}
    }
    List<ActivityType> enabled = const <ActivityType>[];
    if (getIt.isRegistered<ActivitySettingsService>()) {
      final actService = getIt<ActivitySettingsService>();
      try {
        enabled = await actService.getEnabledActivities();
      } catch (_) {
        enabled = actService.cachedEnabledActivities;
      }
    }
    return ActivitySettingsService.isHospitalityResolved(
      sectorMode: sectorMode,
      enabledActivities: enabled,
    );
  }

  @override
  Future<Either<Failure, List<CategoryEntity>>> getCategories() async {
    try {
      var rows = await _localDataSource.getCategories();
      if (rows.isEmpty && await _isHospitalityActive()) {
        await seedDefaultHospitalityCategories();
        rows = await _localDataSource.getCategories();
      }
      final entities = rows.map((r) => CategoryEntity(
        id: r.id,
        name: r.name,
        description: '',
        createdAt: r.createdAt,
      )).toList();
      return Right(entities);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, List<CategoryEntity>>> seedDefaultHospitalityCategories() async {
    try {
      final existing = await _localDataSource.getCategories();
      if (existing.isEmpty) {
        for (var i = 0; i < defaultHospitalityCategories.length; i++) {
          await _localDataSource.addCategory(
            defaultHospitalityCategories[i],
            sortOrder: i,
          );
        }
      }
      final rows = await _localDataSource.getCategories();
      final entities = rows.map((r) => CategoryEntity(
        id: r.id,
        name: r.name,
        description: '',
        createdAt: r.createdAt,
      )).toList();
      return Right(entities);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> addCategory(CategoryEntity category) async {
    try {
      await _localDataSource.addCategory(category.name, description: category.description);
      return const Right(null);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> updateCategory(CategoryEntity category) async {
    try {
      await _localDataSource.updateCategory(category.id, category.name, description: category.description);
      return const Right(null);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> deleteCategory(String id) async {
    try {
      await _localDataSource.deleteCategory(id);
      return const Right(null);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }
}
