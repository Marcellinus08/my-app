/// Model untuk Pengguna (Tuna Netra)
class TunaNetraUser {
  final String uid;
  final String email;
  final String name;
  final String phoneNumber;
  final List<FamilyContact> familyContacts;
  final String pairingCode;
  final DateTime createdAt;
  bool isEmailVerified;

  TunaNetraUser({
    required this.uid,
    required this.email,
    required this.name,
    required this.phoneNumber,
    required this.familyContacts,
    required this.pairingCode,
    required this.createdAt,
    this.isEmailVerified = false,
  });

  /// Convert to Firestore map
  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'email': email,
      'name': name,
      'phoneNumber': phoneNumber,
      'familyContacts': familyContacts.map((c) => c.toMap()).toList(),
      'pairingCode': pairingCode,
      'createdAt': createdAt.toIso8601String(),
      'isEmailVerified': isEmailVerified,
      'userType': 'tunanetra',
    };
  }

  /// Create from Firestore map
  factory TunaNetraUser.fromMap(Map<String, dynamic> map) {
    DateTime parsedDate = DateTime.now();
    
    if (map['createdAt'] != null) {
      if (map['createdAt'] is String) {
        parsedDate = DateTime.parse(map['createdAt']);
      } else if (map['createdAt'] is DateTime) {
        parsedDate = map['createdAt'] as DateTime;
      }
    }
    
    return TunaNetraUser(
      uid: map['uid'] ?? '',
      email: map['email'] ?? '',
      name: map['name'] ?? '',
      phoneNumber: map['phoneNumber'] ?? '',
      familyContacts: (map['familyContacts'] as List?)
              ?.map((c) => FamilyContact.fromMap(c))
              .toList() ??
          [],
      pairingCode: map['pairingCode'] ?? '',
      createdAt: parsedDate,
      isEmailVerified: map['isEmailVerified'] ?? false,
    );
  }
}

/// Model untuk Kontac Keluarga Pengguna
class FamilyContact {
  final String name;
  final String phoneNumber;
  final String? email;

  FamilyContact({
    required this.name,
    required this.phoneNumber,
    this.email,
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'phoneNumber': phoneNumber,
      'email': email,
    };
  }

  factory FamilyContact.fromMap(Map<String, dynamic> map) {
    return FamilyContact(
      name: map['name'] ?? '',
      phoneNumber: map['phoneNumber'] ?? '',
      email: map['email'],
    );
  }
}

/// Model untuk Keluarga (Pengawas)
class FamilyUser {
  final String uid;
  final String email;
  final String name;
  final String phoneNumber;
  final String pairingCode;
  final String pairedUserUid;
  final DateTime createdAt;
  bool isEmailVerified;

  FamilyUser({
    required this.uid,
    required this.email,
    required this.name,
    required this.phoneNumber,
    required this.pairingCode,
    required this.pairedUserUid,
    required this.createdAt,
    this.isEmailVerified = false,
  });

  /// Convert to Firestore map
  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'email': email,
      'name': name,
      'phoneNumber': phoneNumber,
      'pairingCode': pairingCode,
      'pairedUserUid': pairedUserUid,
      'createdAt': createdAt.toIso8601String(),
      'isEmailVerified': isEmailVerified,
      'userType': 'family',
    };
  }

  /// Create from Firestore map
  factory FamilyUser.fromMap(Map<String, dynamic> map) {
    DateTime parsedDate = DateTime.now();
    
    if (map['createdAt'] != null) {
      if (map['createdAt'] is String) {
        parsedDate = DateTime.parse(map['createdAt']);
      } else if (map['createdAt'] is DateTime) {
        parsedDate = map['createdAt'] as DateTime;
      }
    }
    
    return FamilyUser(
      uid: map['uid'] ?? '',
      email: map['email'] ?? '',
      name: map['name'] ?? '',
      phoneNumber: map['phoneNumber'] ?? '',
      pairingCode: map['pairingCode'] ?? '',
      pairedUserUid: map['pairedUserUid'] ?? '',
      createdAt: parsedDate,
      isEmailVerified: map['isEmailVerified'] ?? false,
    );
  }
}
