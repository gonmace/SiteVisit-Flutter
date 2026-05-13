import 'dart:convert';
import '../config/constants.dart';
import '../models/visit.dart';
import 'api_client.dart';

class VisitService {
  final ApiClient _client;
  VisitService({required ApiClient client}) : _client = client;

  Future<List<VisitModel>> fetchVisits() async {
    final resp = await _client.get('${Constants.visitsPath}?page_size=100');
    if (resp.statusCode != 200) throw Exception('Error ${resp.statusCode}');
    final data    = jsonDecode(resp.body) as Map<String, dynamic>;
    final results = (data['results'] as List<dynamic>? ?? []);
    return results.map((j) => VisitModel.fromJson(j as Map<String, dynamic>)).toList();
  }

  Future<VisitModel> updateStatus({
    required int visitId,
    required String newStatus,
    double? latitude,
    double? longitude,
    DateTime? timestamp,
    String? eta,
  }) async {
    final body = <String, dynamic>{
      'status': newStatus,
      if (latitude != null)  'latitude':  latitude,
      if (longitude != null) 'longitude': longitude,
      if (timestamp != null) 'timestamp': timestamp.toUtc().toIso8601String(),
      if (eta != null && eta.isNotEmpty) 'eta': eta,
    };
    final resp = await _client.post('${Constants.visitsPath}$visitId/status/', body);
    if (resp.statusCode != 200) throw Exception('Error ${resp.statusCode}: ${resp.body}');
    return VisitModel.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  Future<VisitModel> updateNotas({required int visitId, required String notas}) async {
    final resp = await _client.patch('${Constants.visitsPath}$visitId/notas/', {'notas': notas});
    if (resp.statusCode != 200) throw Exception('Error ${resp.statusCode}: ${resp.body}');
    return VisitModel.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  Future<void> uploadPhoto({
    required int visitId,
    required String photoType,
    required String imagePath,
    double? latitude,
    double? longitude,
    String? description,
    DateTime? takenAt,
  }) async {
    final resp = await _client.multipart(
      '${Constants.visitsPath}$visitId/photos/',
      {
        'photo_type': photoType,
        'taken_at':   (takenAt ?? DateTime.now()).toUtc().toIso8601String(),
        if (latitude != null)                    'latitude':    latitude.toString(),
        if (longitude != null)                   'longitude':   longitude.toString(),
        if (description != null && description.isNotEmpty) 'description': description,
      },
      {'image': imagePath},
    );
    if (resp.statusCode != 201) throw Exception('Photo upload failed: ${resp.statusCode}');
  }

  Future<void> uploadTrackingPoint({
    required int visitId,
    required String event,
    required double latitude,
    required double longitude,
    required DateTime timestamp,
  }) async {
    final body = {
      'event':     event,
      'latitude':  latitude,
      'longitude': longitude,
      'timestamp': timestamp.toUtc().toIso8601String(),
    };
    final resp = await _client.post('${Constants.visitsPath}$visitId/tracking/', body);
    if (resp.statusCode != 201) throw Exception('Tracking failed: ${resp.statusCode}');
  }
}
