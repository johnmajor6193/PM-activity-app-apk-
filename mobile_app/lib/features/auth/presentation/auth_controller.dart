import 'package:flutter/foundation.dart';

import '../data/dev_login_auth_repository.dart';
import '../domain/auth_failure.dart';
import '../domain/entities/employee_profile.dart';
import '../domain/repositories/auth_repository.dart';

enum AuthStatus { idle, loading, success, error }

/// Holds login UI state and talks to [AuthRepository]. LoginScreen depends
/// only on this controller, not on how authentication is implemented, so
/// swapping DevLoginAuthRepository for an OTP-based repository later needs
/// no screen changes.
class AuthController extends ChangeNotifier {
  AuthController({AuthRepository? repository}) : _repository = repository ?? DevLoginAuthRepository();

  final AuthRepository _repository;

  AuthStatus status = AuthStatus.idle;
  String? errorMessage;
  EmployeeProfile? profile;

  bool get isLoading => status == AuthStatus.loading;

  // Login is a real network call: if the screen is popped while one is
  // in flight (e.g. the user backs out), the pending `login()` must not
  // call notifyListeners() after this controller is disposed — Flutter
  // throws for that. Guards every notifyListeners() call below.
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (_disposed) {
      return;
    }
    super.notifyListeners();
  }

  Future<void> login({required String employeeId, required String mobileNumber}) async {
    status = AuthStatus.loading;
    errorMessage = null;
    notifyListeners();

    try {
      final result = await _repository.login(
        employeeId: employeeId,
        mobileNumber: mobileNumber,
      );
      profile = result.profile;
      status = AuthStatus.success;
    } on AuthFailure catch (failure) {
      errorMessage = failure.message;
      status = AuthStatus.error;
    } catch (_) {
      errorMessage = 'Something went wrong. Please try again.';
      status = AuthStatus.error;
    }
    notifyListeners();
  }
}
