import '../entities/employee_profile.dart';

/// What a successful login returns.
class AuthResult {
  const AuthResult({required this.accessToken, required this.profile});

  final String accessToken;
  final EmployeeProfile profile;
}

/// Abstraction over however employee login is currently implemented.
///
/// The presentation layer (AuthController, LoginScreen) depends only on
/// this interface. The initial implementation
/// (DevLoginAuthRepository, in ../data/) authenticates via Employee ID +
/// mobile number against the backend's development/test login endpoint.
/// Swapping in an OTP-based implementation later means adding a new
/// class here and changing nothing in the presentation layer.
abstract class AuthRepository {
  Future<AuthResult> login({
    required String employeeId,
    required String mobileNumber,
  });
}
