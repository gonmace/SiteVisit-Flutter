import 'dart:convert';
import '../config/constants.dart';
import '../models/site.dart';
import 'api_client.dart';

class SiteService {
  final ApiClient _client;
  SiteService({required ApiClient client}) : _client = client;

  Future<List<SiteModel>> fetchSites() async {
    final resp = await _client.get('${Constants.sitesPath}?page_size=500');
    if (resp.statusCode != 200) throw Exception('Error ${resp.statusCode}');
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final results = (data['results'] as List<dynamic>? ?? []);
    return results.map((j) => SiteModel.fromJson(j as Map<String, dynamic>)).toList();
  }
}
