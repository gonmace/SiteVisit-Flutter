class UserModel {
  final int id;
  final String email;
  final String role;
  final String company;
  final String firstName;
  final String lastName;
  final String cargo;
  final String phone;
  final String rut;
  final String? photoUrl;

  const UserModel({
    required this.id,
    required this.email,
    required this.role,
    required this.company,
    this.firstName = '',
    this.lastName = '',
    this.cargo = '',
    this.phone = '',
    this.rut = '',
    this.photoUrl,
  });

  String get fullName {
    final name = '$firstName $lastName'.trim();
    return name.isNotEmpty ? name : email;
  }

  bool get isTechnician => role == 'technician';
  bool get isManager => role == 'manager' || role == 'super_manager';
  bool get isSuperManager => role == 'super_manager';
  bool get isViewer => role == 'viewer';
}
