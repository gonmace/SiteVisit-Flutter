import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../config/constants.dart';
import 'api_client.dart';

class ThemeService {
  final ApiClient _client;
  ThemeService({required ApiClient client}) : _client = client;

  Future<Map<String, String>> fetchTheme(String company) async {
    try {
      final resp = await _client.get('${Constants.themePath}?company=$company');
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        return data.map((k, v) => MapEntry(k, v.toString()));
      }
    } catch (e) {
      debugPrint('ThemeService.fetchTheme error: $e');
    }
    return {};
  }
}
