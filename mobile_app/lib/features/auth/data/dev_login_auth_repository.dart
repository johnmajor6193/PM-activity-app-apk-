import '../domain/entities/employee_profile.dart';
import '../domain/repositories/auth_repository.dart';
import 'auth_api_client.dart';

/// [AuthRepository] backed by the backend's development/test login
/// endpoint (Employee ID + mobile number, no OTP, no password).
///
/// For local/dev and QA use only. To switch to production OTP-based
/// login later, add an `OtpAuthRepository` implementing [AuthRepository]
/// and use it instead here — AuthController and the screens are
/// unaffected.
class DevLoginAuthRepository implements AuthRepository {
  DevLoginAuthRepository({AuthApiClient? apiClient}) : _apiClient = apiClient ?? AuthApiClient();

  final AuthApiClient _apiClient;

  @override
  Future<AuthResult> login({
    required String employeeId,
    required String mobileNumber,
  }) async {
    final json = await _apiClient.login(
      employeeId: employeeId,
      mobileNumber: mobileNumber,
    );

    final employeeJson = json['employee'] as Map<String, dynamic>;
    return AuthResult(
      accessToken: json['access_token'] as String,
      profile: EmployeeProfile(
        employeeId: employeeJson['employee_id'] as String,
        name: employeeJson['name'] as String,
        assignedDistrict: employeeJson['assigned_district'] as String?,
      ),
    );
  }
}
