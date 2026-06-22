import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class PendingRegistration {
  final String userType;
  final String email;
  final String name;
  final String phoneNumber;
  final String pairingCode;
  final DateTime createdAt;

  PendingRegistration({
    required this.userType,
    required this.email,
    required this.name,
    required this.phoneNumber,
    this.pairingCode = '',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  bool get isExpired =>
      DateTime.now().difference(createdAt).inMinutes >= 10;

  Map<String, dynamic> toMap() => {
    'userType': userType,
    'email': email,
    'name': name,
    'phoneNumber': phoneNumber,
    'pairingCode': pairingCode,
    'createdAt': createdAt.toIso8601String(),
  };

  factory PendingRegistration.fromMap(Map<String, dynamic> map) {
    return PendingRegistration(
      userType: map['userType'] as String? ?? '',
      email: map['email'] as String? ?? '',
      name: map['name'] as String? ?? '',
      phoneNumber: map['phoneNumber'] as String? ?? '',
      pairingCode: map['pairingCode'] as String? ?? '',
      createdAt: map['createdAt'] != null
          ? DateTime.tryParse(map['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

class PendingRegistrationService {
  static const _storageKey = 'pending_email_registration';

  Future<void> save(PendingRegistration registration) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_storageKey, jsonEncode(registration.toMap()));
  }

  Future<PendingRegistration?> load() async {
    final preferences = await SharedPreferences.getInstance();
    final value = preferences.getString(_storageKey);
    if (value == null || value.isEmpty) return null;

    try {
      return PendingRegistration.fromMap(
        Map<String, dynamic>.from(jsonDecode(value) as Map),
      );
    } catch (_) {
      await clear();
      return null;
    }
  }

  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_storageKey);
  }
}
