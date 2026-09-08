/// Base failure class for domain/data layer error handling
abstract class Failure {
  final String message;
  final int? statusCode;

  const Failure(this.message, [this.statusCode]);

  @override
  String toString() => message;
}

class ServerFailure extends Failure {
  const ServerFailure(super.message, [super.statusCode]);
}

class NetworkFailure extends Failure {
  const NetworkFailure([super.message = 'Network connection failed. Please check your internet.']);
}

class AuthFailure extends Failure {
  const AuthFailure([super.message = 'Authentication failed. Please log in again.', super.statusCode = 401]);
}

class ValidationFailure extends Failure {
  final Map<String, dynamic>? errors;
  const ValidationFailure(String message, {this.errors}) : super(message, 400);
}

class CacheFailure extends Failure {
  const CacheFailure([super.message = 'Failed to load cached data.']);
}
