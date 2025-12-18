import '../utils/constants.dart';

class UserModel {
  final String id;
  final String email;
  final String name;
  final UserType userType;
  final String? phoneNumber;
  final String? connectedUserId; // ID tunanetra yang dimonitor (untuk family)
  final DateTime createdAt;
  final DateTime? lastActive;

  UserModel({
    required this.id,
    required this.email,
    required this.name,
    required this.userType,
    this.phoneNumber,
    this.connectedUserId,
    required this.createdAt,
    this.lastActive,
  });

  // Convert from Firestore
  factory UserModel.fromMap(Map<String, dynamic> map, String id) {
    return UserModel(
      id: id,
      email: map['email'] ?? '',
      name: map['name'] ?? '',
      userType: map['userType'] == 'tunanetra' 
          ? UserType.tunanetra 
          : UserType.family,
      phoneNumber: map['phoneNumber'],
      connectedUserId: map['connectedUserId'],
      createdAt: DateTime.parse(map['createdAt']),
      lastActive: map['lastActive'] != null 
          ? DateTime.parse(map['lastActive']) 
          : null,
    );
  }

  // Convert to Firestore
  Map<String, dynamic> toMap() {
    return {
      'email': email,
      'name': name,
      'userType': userType == UserType.tunanetra ? 'tunanetra' : 'family',
      'phoneNumber': phoneNumber,
      'connectedUserId': connectedUserId,
      'createdAt': createdAt.toIso8601String(),
      'lastActive': lastActive?.toIso8601String(),
    };
  }

  UserModel copyWith({
    String? id,
    String? email,
    String? name,
    UserType? userType,
    String? phoneNumber,
    String? connectedUserId,
    DateTime? createdAt,
    DateTime? lastActive,
  }) {
    return UserModel(
      id: id ?? this.id,
      email: email ?? this.email,
      name: name ?? this.name,
      userType: userType ?? this.userType,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      connectedUserId: connectedUserId ?? this.connectedUserId,
      createdAt: createdAt ?? this.createdAt,
      lastActive: lastActive ?? this.lastActive,
    );
  }
}
