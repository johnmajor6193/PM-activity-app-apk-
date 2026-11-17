/// Backend API configuration.
class ApiConfig {
  /// Base URL of the FastAPI backend.
  ///
  /// Defaults to the Android emulator's alias for the host machine's
  /// localhost. Override for a physical device or other environment
  /// with `flutter run --dart-define=API_BASE_URL=http://<host>:8000`.
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );
}
