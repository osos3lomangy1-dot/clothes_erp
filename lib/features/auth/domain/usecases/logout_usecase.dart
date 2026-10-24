import 'package:injectable/injectable.dart';
import '../repositories/auth_repository.dart';

@lazySingleton
class LogoutUseCase {
  final AuthRepository _repository;

  LogoutUseCase(this._repository);

  Future<void> call() {
    return _repository.logout();
  }
}
