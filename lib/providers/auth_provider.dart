import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import '../services/user_service.dart';
import '../services/otp_service.dart';
import '../utils/constants.dart';

/// Auth Provider - Manages authentication state globally
/// Provides auth status, user data, and auth operations
class AuthProvider with ChangeNotifier {
  final AuthService _authService = AuthService();
  final UserService _userService = UserService();

  // State variables
  User? _currentUser;
  Map<String, dynamic>? _userData;
  bool _isLoading = false;
  String? _errorMessage;
  bool _isAuthenticated = false;
  String? _registrationEmail; // Temp store during registration flow

  // Getters
  User? get currentUser => _currentUser;
  Map<String, dynamic>? get userData => _userData;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated => _isAuthenticated;
  String? get registrationEmail => _registrationEmail;

  /// Initialize auth state from Firebase
  /// Call this in main() or app initialization
  void initializeAuth() {
    _authService.authStateChanges.listen((User? user) {
      _currentUser = user;
      _isAuthenticated = user != null;
      
      if (user != null) {
        _loadUserData(user.uid);
      } else {
        _userData = null;
      }
      
      notifyListeners();
    });
  }

  /// Load user data from Firestore
  Future<void> _loadUserData(String uid) async {
    try {
      final data = await _userService.getUserData(uid);
      _userData = data;
      notifyListeners();
    } catch (e) {
      print('❌ Error loading user data: $e');
      _errorMessage = 'Failed to load user data';
      notifyListeners();
    }
  }

  /// Request OTP for registration
  Future<bool> requestRegistrationOtp(String email) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      final success = await _authService.requestRegistrationOtp(email);
      
      if (success) {
        _registrationEmail = email;
        _isLoading = false;
        notifyListeners();
        return true;
      }
      
      throw Exception('Failed to request OTP');
    } catch (e) {
      _isLoading = false;
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      rethrow;
    }
  }

  /// Resend OTP for registration
  Future<bool> resendRegistrationOtp(String email) async {
    try {
      _errorMessage = null;
      notifyListeners();

      final otpService = OtpService();
      final success = await otpService.resendOtp(email);
      
      if (success) {
        _registrationEmail = email;
        notifyListeners();
        return true;
      }
      
      throw Exception('Failed to resend OTP');
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      rethrow;
    }
  }

  /// Complete registration with OTP
  Future<bool> registerWithOtp({
    required String email,
    required String otp,
    required String name,
    required UserType userType,
    required String phoneNumber,
    String? pairedUserUid,
  }) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      // Verify OTP and register
      final user = await _authService.registerWithOtp(
        email,
        otp,
        name,
        userType,
      );

      if (user == null) {
        throw Exception('Registration failed - user creation returned null');
      }

      // Save user profile based on type
      if (userType == UserType.tunanetra) {
        await _userService.saveTunaNetraUser(
          uid: user.uid,
          email: email,
          name: name,
          phoneNumber: phoneNumber,
          pairingCode: '', // Will be generated later if needed
          familyContacts: [],
        );
      } else {
        await _userService.saveFamilyUser(
          uid: user.uid,
          email: email,
          name: name,
          phoneNumber: phoneNumber,
          pairingCode: '',
          pairedUserUid: pairedUserUid ?? '',
        );
      }

      _currentUser = user;
      _isAuthenticated = true;
      _registrationEmail = null;
      _isLoading = false;
      
      // Load user data
      await _loadUserData(user.uid);
      
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      rethrow;
    }
  }

  /// Request OTP for login
  Future<bool> requestLoginOtp(String email) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      final success = await _authService.requestLoginOtp(email);
      
      if (success) {
        _registrationEmail = email; // Temporary store
        _isLoading = false;
        notifyListeners();
        return true;
      }
      
      throw Exception('Failed to request OTP');
    } catch (e) {
      _isLoading = false;
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      rethrow;
    }
  }

  /// Complete login with OTP
  Future<bool> loginWithOtp(String email, String otp) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      final uid = await _authService.loginWithOtp(email, otp);

      if (uid == null) {
        throw Exception('Login failed - UID not found');
      }

      // Update user data
      await _loadUserData(uid);
      _isAuthenticated = true;
      _registrationEmail = null;
      _isLoading = false;
      
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      rethrow;
    }
  }

  /// Logout user
  Future<void> logout() async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      await _authService.logout();

      _currentUser = null;
      _userData = null;
      _isAuthenticated = false;
      _registrationEmail = null;
      _isLoading = false;
      
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      rethrow;
    }
  }

  /// Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Get user by email
  Future<Map<String, dynamic>?> getUserByEmail(String email) async {
    try {
      return await _authService.getUserByEmail(email);
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      return null;
    }
  }
}
