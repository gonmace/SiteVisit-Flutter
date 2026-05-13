class TechnicianSearchResult {
  final int id;
  final String firstName;
  final String lastName;
  final String company;
  final String rut;
  final String email;
  final String cargo;
  final String? photoUrl;

  TechnicianSearchResult({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.company,
    required this.rut,
    required this.email,
    required this.cargo,
    this.photoUrl,
  });

  factory TechnicianSearchResult.fromJson(Map<String, dynamic> json) {
    return TechnicianSearchResult(
      id:        json['id']        as int,
      firstName: json['first_name'] as String? ?? '',
      lastName:  json['last_name']  as String? ?? '',
      company:   json['company']    as String? ?? '',
      rut:       json['rut']        as String? ?? '',
      email:     json['email']      as String? ?? '',
      cargo:     json['cargo']      as String? ?? '',
      photoUrl:  json['photo_url']  as String?,
    );
  }

  String get fullName => '$firstName $lastName';

  String get companyLabel => company == 'wom' ? 'WOM' : 'PTI';
}
