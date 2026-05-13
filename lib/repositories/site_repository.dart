import 'package:flutter/cupertino.dart';

import '../models/site.dart';
import '../services/offline_manager.dart';

class SiteRepository extends ChangeNotifier {
  final OfflineManager _offline;

  SiteRepository({required OfflineManager offlineManager})
      : _offline = offlineManager;

  List<SiteModel> _sites = [];
  List<SiteModel> get sites => _sites;

  bool _loading = false;
  bool get loading => _loading;

  String? _error;
  String? get error => _error;

  Future<void> fetchSites() async {
    if (_loading) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _sites = await _offline.fetchSites();
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}
