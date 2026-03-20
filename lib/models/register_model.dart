/// Model untuk Register Form - Pengguna (Tuna Netra)
class RegisterUserModel {
  final String fullName;
  final String phoneNumber;
  final String familyPhoneNumber;
  final String username;
  final String password;

  RegisterUserModel({
    required this.fullName,
    required this.phoneNumber,
    required this.familyPhoneNumber,
    required this.username,
    required this.password,
  });
}

/// Model untuk Register Form - Keluarga
class RegisterFamilyModel {
  final String fullName;
  final String phoneNumber;
  final String username;
  final String password;

  RegisterFamilyModel({
    required this.fullName,
    required this.phoneNumber,
    required this.username,
    required this.password,
  });
}
