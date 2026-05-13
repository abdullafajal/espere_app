/// Connectivity service — monitors network status and triggers sync.
import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityService {
  static final Connectivity _connectivity = Connectivity();
  static StreamSubscription<List<ConnectivityResult>>? _subscription;
  static bool _isOnline = true;
  static final _onReconnect = StreamController<void>.broadcast();

  /// Whether the device currently has network connectivity.
  static bool get isOnline => _isOnline;

  /// Stream that emits when device comes back online.
  static Stream<void> get onReconnect => _onReconnect.stream;

  /// Initialize connectivity monitoring.
  static Future<void> init() async {
    // Check initial status
    final results = await _connectivity.checkConnectivity();
    _isOnline = !results.contains(ConnectivityResult.none);

    // Listen for changes
    _subscription = _connectivity.onConnectivityChanged.listen((results) {
      final wasOffline = !_isOnline;
      _isOnline = !results.contains(ConnectivityResult.none);

      if (wasOffline && _isOnline) {
        // Device just came back online — trigger sync
        _onReconnect.add(null);
      }
    });
  }

  /// Dispose of the subscription.
  static void dispose() {
    _subscription?.cancel();
    _onReconnect.close();
  }
}
