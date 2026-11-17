import 'package:connectivity_plus/connectivity_plus.dart';

/// Reports whether this device currently has a network connection.
///
/// This only detects that sync is *possible* right now (Wi-Fi/mobile
/// attached) — it says nothing about whether an upload would actually
/// succeed; that is DriveUploadService's job, once one exists.
class ConnectivityService {
  ConnectivityService({Connectivity? connectivity}) : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  Future<bool> hasConnection() async {
    final results = await _connectivity.checkConnectivity();
    return _hasAnyConnection(results);
  }

  /// Emits whenever the device's connectivity changes from none to
  /// some, or some to none.
  Stream<bool> get onConnectivityChanged =>
      _connectivity.onConnectivityChanged.map(_hasAnyConnection);

  bool _hasAnyConnection(List<ConnectivityResult> results) =>
      results.any((result) => result != ConnectivityResult.none);
}
