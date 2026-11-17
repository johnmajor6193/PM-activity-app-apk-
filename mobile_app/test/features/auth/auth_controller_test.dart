import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/auth/domain/auth_failure.dart';
import 'package:mobile_app/features/auth/domain/entities/employee_profile.dart';
import 'package:mobile_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:mobile_app/features/auth/presentation/auth_controller.dart';

/// Stands in for the real AuthRepository so the controller's state
/// transitions can be tested without a network call.
class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository.success()
      : _result = const AuthResult(
          accessToken: 'fake-token',
          profile: EmployeeProfile(
            employeeId: 'ENG001',
            name: 'Dev Test Engineer',
            assignedDistrict: 'Chennai',
          ),
        ),
        _failure = null;

  _FakeAuthRepository.failure(String message)
      : _result = null,
        _failure = AuthFailure(message);

  final AuthResult? _result;
  final AuthFailure? _failure;

  @override
  Future<AuthResult> login({
    required String employeeId,
    required String mobileNumber,
  }) async {
    if (_failure != null) {
      throw _failure;
    }
    return _result!;
  }
}

void main() {
  test('login success populates profile and sets status to success', () async {
    final controller = AuthController(repository: _FakeAuthRepository.success());

    await controller.login(employeeId: 'ENG001', mobileNumber: '9876543210');

    expect(controller.status, AuthStatus.success);
    expect(controller.profile?.employeeId, 'ENG001');
    expect(controller.profile?.assignedDistrict, 'Chennai');
    expect(controller.errorMessage, isNull);
  });

  test('login failure sets error message and status to error', () async {
    final controller = AuthController(
      repository: _FakeAuthRepository.failure('Invalid Employee ID or mobile number.'),
    );

    await controller.login(employeeId: 'BAD', mobileNumber: '0000000000');

    expect(controller.status, AuthStatus.error);
    expect(controller.errorMessage, 'Invalid Employee ID or mobile number.');
    expect(controller.profile, isNull);
  });
}
