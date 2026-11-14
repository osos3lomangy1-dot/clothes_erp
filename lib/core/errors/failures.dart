abstract class Failure {
  final String message;
  const Failure(this.message);
}

class ServerFailure extends Failure {
  const ServerFailure(super.message);
}

class CacheFailure extends Failure {
  const CacheFailure(super.message);
}

class AuthFailure extends Failure {
  const AuthFailure(super.message);
}

class DependencyBlockedFailure extends Failure {
  final String blockedBy;
  const DependencyBlockedFailure(this.blockedBy)
      : super('لا يمكن تعطيل هذه الميزة لأنها مطلوبة لميزة مفعّلة: $blockedBy');
}

class FeatureDisabledFailure extends Failure {
  final String featureKey;
  const FeatureDisabledFailure(this.featureKey)
      : super('الميزة غير مفعّلة: $featureKey');
}

class ValidationFailure extends Failure {
  const ValidationFailure(super.message);
}
