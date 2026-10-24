import 'package:equatable/equatable.dart';

class CategoryEntity extends Equatable {
  final String id;
  final String name;
  final String description;
  final DateTime createdAt;

  const CategoryEntity({
    required this.id,
    required this.name,
    required this.description,
    required this.createdAt,
  });

  @override
  List<Object?> get props => [id, name, description, createdAt];
}
