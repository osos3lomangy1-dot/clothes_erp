import 'package:equatable/equatable.dart';

class ProductEntity extends Equatable {
  final String id;
  final String name;
  final String description;
  final String categoryId;
  final String categoryName;
  final DateTime createdAt;

  const ProductEntity({
    required this.id,
    required this.name,
    required this.description,
    required this.categoryId,
    required this.categoryName,
    required this.createdAt,
  });

  @override
  List<Object?> get props => [id, name, description, categoryId, categoryName, createdAt];
}
