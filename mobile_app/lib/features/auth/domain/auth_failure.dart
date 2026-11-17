/// Error raised by [AuthRepository.login] (see repositories/auth_repository.dart),
/// carrying a message safe to show to the user.
class AuthFailure implements Exception {
  const AuthFailure(this.message);

  final String message;

  @override
  String toString() => message;
}
