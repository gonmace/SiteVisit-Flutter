class SiteModel {
  final int id;
  final String code;
  final String operatorCode;
  final String name;
  final double latitude;
  final double longitude;
  final String company;

  const SiteModel({
    required this.id,
    required this.code,
    required this.operatorCode,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.company,
  });

  factory SiteModel.fromJson(Map<String, dynamic> json) => SiteModel(
    id:           json['id'] as int,
    code:         json['code'] as String,
    operatorCode: json['operator_code'] as String? ?? '',
    name:         json['name'] as String,
    latitude:     (json['latitude'] as num).toDouble(),
    longitude:    (json['longitude'] as num).toDouble(),
    company:      json['company'] as String,
  );

  String get displayName => '$code — $name';
}
