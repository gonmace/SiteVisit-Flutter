import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

class ConnectivityRepository extends ChangeNotifier {
  bool? _isOnline;

  // Pesimista por defecto: false hasta que checkConnectivity() resuelva.
  // Evita el falso positivo "online" al arrancar sin red.
  bool get isOnline => _isOnline ?? false;
  bool get isUnknown => _isOnline == null;

  ConnectivityRepository() {
    Connectivity().checkConnectivity().then(_update);
    Connectivity().onConnectivityChanged.listen(_update);
  }

  void _update(dynamic result) {
    final results = result is List ? result : [result];
    final online = results.any((r) => r != ConnectivityResult.none);
    if (online != _isOnline) {
      _isOnline = online;
      notifyListeners();
    }
  }
}
