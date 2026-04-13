# Register Screen Update - Implementation Guide

## Perubahan yang Diperlukan

### 1. Tambah Password Controller di _RegisterScreenState
```dart
// Tambahkan di initState()
late TextEditingController _userPasswordController;

// Tambahkan di initState()
_userPasswordController = TextEditingController();

// Tambahkan di dispose()
_userPasswordController.dispose();
```

### 2. Tambah Password Validator
```dart
String? _validatePassword(String? value) {
  if (value == null || value.isEmpty) return 'Password harus diisi';
  if (value.length < 6) return 'Password minimal 6 karakter';
  return null;
}
```

### 3. Tambah Email Exists Check Function
```dart
Future<bool> _checkEmailExists(String email) async {
  try {
    email = email.toLowerCase().trim();
    print('🔍 Checking if email exists: $email');
    
    final exists = await _authService.emailExists(email);
    
    if (exists) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('❌ Email sudah terdaftar!'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      print('⚠️ Email already registered');
    } else {
      print('✅ Email available');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('✅ Email tersedia!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
    
    return !exists;
  } catch (e) {
    print('❌ Error checking email: $e');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ ${e.toString().replaceAll("Exception: ", "")}'),
          backgroundColor: Colors.red,
        ),
      );
    }
    return false;
  }
}
```

### 4. Update _handlePengunaRegister to Include Email Check dan Password
```dart
Future<void> _handlePengunaRegister() async {
  // Validate email terlebih dahulu
  final emailValidation = _validateEmail(_userEmailController.text);
  if (emailValidation != null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(emailValidation), backgroundColor: Colors.red),
    );
    return;
  }

  // Validate password
  final passwordValidation = _validatePassword(_userPasswordController.text);
  if (passwordValidation != null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(passwordValidation), backgroundColor: Colors.red),
    );
    return;
  }

  // Validate other fields
  if (!_pengunaFormKey.currentState!.validate()) {
    return;
  }

  setState(() => _isLoading = true);

  try {
    final email = _userEmailController.text.trim();
    
    print('\n[UI] Checking if email exists...');
    final emailExists = await _authService.emailExists(email);
    
    if (emailExists) {
      throw Exception('Email sudah terdaftar. Gunakan email lain.');
    }
    
    print('✅ Email available, sending OTP...');
    
    // Send OTP
    final success = await _authService.requestRegistrationOtp(email);
    
    if (!success) {
      throw Exception('Gagal mengirim OTP');
    }

    if (mounted) {
      setState(() => _pengunaOtpSent = true);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '✅ OTP telah dikirim!\n'
            'Masukkan kode 6-digit dari email: $email',
            style: const TextStyle(height: 1.4),
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  } catch (e) {
    if (mounted) {
      String errorMsg = e.toString().replaceAll("Exception: ", "");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ $errorMsg'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  } finally {
    if (mounted) setState(() => _isLoading = false);
  }
}
```

### 5. Update _handlePengunaVerifyOtp untuk Include Password
```dart
Future<void> _handlePengunaVerifyOtp() async {
  if (!_pengunaFormKey.currentState!.validate()) {
    return;
  }

  setState(() => _isLoading = true);

  try {
    final email = _userEmailController.text.trim();
    final password = _userPasswordController.text;
    final otp = _userOtpController.text.trim();
    final name = _userNameController.text.trim();
    final phone = _userPhoneController.text.trim();
    
    print('\n[UI] Verifying OTP and registering...');
    print('   Email: $email');
    print('   Name: $name');
    print('   Phone: $phone');

    // Call new method registerWithEmailPasswordAndOtp
    final user = await _authService.registerWithEmailPasswordAndOtp(
      email: email,
      password: password,
      otp: otp,
      name: name,
      phoneNumber: phone,
      userType: UserType.tunanetra,
    );

    if (user == null) {
      throw Exception('Registrasi gagal');
    }

    final userId = user.uid;
    print('   ✅ User created: $userId');

    print('   📌 Generating pairing code...');
    String pairingCode = _pairingService.generatePairingCode();
    
    print('   📌 Saving pairing code...');
    await _pairingService.savePairingCode(userId, pairingCode);

    final familyContact = FamilyContact(
      name: _familyNameController.text.trim(),
      phoneNumber: _familyPhoneController.text.trim(),
    );

    print('   📌 Saving user data...');
    await _userService.saveTunaNetraUser(
      uid: userId,
      email: email,
      name: name,
      phoneNumber: phone,
      pairingCode: pairingCode,
      familyContacts: [familyContact],
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Registrasi berhasil!\nKode pairing: $pairingCode'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 4),
        ),
      );

      await Future.delayed(const Duration(milliseconds: 500));
      Navigator.pushReplacementNamed(context, AppRoutes.login);
    }
  } catch (e) {
    if (mounted) {
      String errorMsg = e.toString().replaceAll("Exception: ", "");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ $errorMsg'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  } finally {
    if (mounted) setState(() => _isLoading = false);
  }
}
```

### 6. Update UI Form - Tambah Password Field (sebelum nama)
```dart
// Add this after email field and before name field in build() method
const SizedBox(height: 18),

// Password Field
ModernTextField(
  controller: _userPasswordController,
  label: 'Password',
  icon: Icons.lock_rounded,
  semanticLabel: 'Password untuk akun Anda',
  obscureText: true,
  validator: _validatePassword,
),
```

## FLOW BARU:

```
1. User input Email
   ↓
2. Klik "Lanjut" atau tombol cek email
   ↓
3. Sistem cek: apakah email sudah terdaftar?
   ├─ Jika ya: Tampilkan error "Email sudah terdaftar"
   └─ Jika tidak: Lanjut ke step 4
   ↓
4. Tampilkan fields: Password + Nama + Nomor HP
   ↓
5. User input semua fields
   ↓
6. Klik "Daftar" / "Kirim OTP"
   ↓
7. Sistem:
   - Validate semua fields
   - Cek email exists lagi (double check)
   - Kirim OTP ke email
   ↓
8. Tampilkan field input OTP
   ↓
9. User input OTP
   ↓
10. Klik "Verifikasi"
    ↓
11. Sistem:
    - Verify OTP
    - Create Firebase Auth user dengan email+password
    - Save user data ke Firestore
    - Generate pairing code
    ↓
12. Success! Navigate ke Login screen
```

## Tips Implementasi:

1. **State Management**: Pertimbangkan untuk split screen into 2 states:
   - State 1: Email check
   - State 2: Form + OTP verification

2. **Email Validation**: Gunakan method `emailExists()` yang sudah ditambahkan di AuthService

3. **Error Messages**: Pastikan messages user-friendly dan dalam Bahasa Indonesia

4. **Loading State**: Tampilkan loading indicator selama proses berlangsung

5. **Security**: Password sudah di-hash oleh Firebase Auth, tidak perlu di-hash manual

---

## Testing:

1. Coba register dengan email baru → harus berhasil sampai OTP
2. Coba register dengan email yang sama 2x → harus error di step email check
3. Coba verify dengan OTP salah → harus error
4. Coba login dengan email+password yg baru dibuat → harus berhasil

