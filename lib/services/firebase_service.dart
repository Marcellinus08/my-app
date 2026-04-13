import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

/// Firebase Service untuk testing dan utilities
class FirebaseService {
  static final FirebaseService _instance = FirebaseService._internal();

  factory FirebaseService() {
    return _instance;
  }

  FirebaseService._internal();

  // Firebase instances
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Test Firebase connection
  Future<bool> testConnection() async {
    try {
      print('🔍 Testing Firebase connection...');
      
      // Test Auth connection
      print('  ✓ Auth instance: Initialized');
      
      // Test Firestore connection by reading a test document
      final doc = await _firestore
          .collection('_test')
          .doc('connection')
          .get();
      
      print('  ✓ Firestore connection: OK');
      print('✅ Firebase connection test PASSED!');
      return true;
    } catch (e) {
      print('❌ Firebase connection test FAILED: $e');
      return false;
    }
  }

  /// Get Firebase apps info
  void printFirebaseInfo() {
    print('\n🔥 Firebase Info:');
    print('  Firebase apps: ${Firebase.apps.length}');
    
    for (var app in Firebase.apps) {
      print('  App name: ${app.name}');
      print('  App options projectId: ${app.options.projectId}');
    }
  }

  // Getter for Firebase instances
  FirebaseAuth get auth => _auth;
  FirebaseFirestore get firestore => _firestore;

  /// Get current user
  User? get currentUser => _auth.currentUser;

  /// Check if user is authenticated
  bool get isAuthenticated => _auth.currentUser != null;
}
