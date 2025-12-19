import 'package:flutter/material.dart';
import '../../utils/constants.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneController = TextEditingController();
  
  bool _isLoading = false;
  bool _obscurePassword = true;
  UserType? _userType;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _userType = ModalRoute.of(context)?.settings.arguments as UserType?;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);

      await Future.delayed(const Duration(milliseconds: 500));

      if (!mounted) return;
      
      setState(() => _isLoading = false);
      
      // Kembali ke login screen
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    String title = _userType == UserType.tunanetra 
        ? 'Daftar Pengguna' 
        : 'Daftar Keluarga';

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: _userType == UserType.tunanetra
              ? AppColors.primaryGradient
              : AppColors.accentGradient,
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Modern AppBar
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back_rounded, size: 28),
                        color: Colors.white,
                        onPressed: () {
                          Navigator.pop(context);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      title,
                      style: AppTextStyles.heading3.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              
              Expanded(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      children: [
                        const SizedBox(height: 10),
                        
                        // Icon Container
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: Icon(
                            _userType == UserType.tunanetra 
                                ? Icons.person_add_rounded 
                                : Icons.family_restroom_rounded,
                            size: 70,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 24),
                        
                        // Title
                        Text(
                          'Buat Akun Baru',
                          style: AppTextStyles.heading1.copyWith(
                            color: Colors.white,
                            fontSize: 32,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Daftarkan diri Anda',
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 16,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 30),
                        
                        // Register Card
                        Container(
                          padding: const EdgeInsets.all(28),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(30),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 20,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _buildModernTextField(
                                  controller: _nameController,
                                  label: 'Nama Lengkap',
                                  icon: Icons.person_rounded,
                                  semanticLabel: 'Kolom input nama lengkap',
                                ),
                                const SizedBox(height: 16),
                                
                                _buildModernTextField(
                                  controller: _emailController,
                                  label: 'Email',
                                  icon: Icons.email_rounded,
                                  keyboardType: TextInputType.emailAddress,
                                  semanticLabel: 'Kolom input email',
                                ),
                                const SizedBox(height: 16),
                                
                                _buildModernTextField(
                                  controller: _phoneController,
                                  label: 'Nomor Telepon',
                                  icon: Icons.phone_rounded,
                                  keyboardType: TextInputType.phone,
                                  semanticLabel: 'Kolom input nomor telepon',
                                ),
                                const SizedBox(height: 16),
                                
                                _buildModernTextField(
                                  controller: _passwordController,
                                  label: 'Password',
                                  icon: Icons.lock_rounded,
                                  obscureText: _obscurePassword,
                                  semanticLabel: 'Kolom input password',
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_off_rounded
                                          : Icons.visibility_rounded,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _obscurePassword = !_obscurePassword;
                                      });
                                    },
                                  ),
                                ),
                                const SizedBox(height: 30),
                                
                                // Register Button
                                _isLoading
                                    ? const Center(child: CircularProgressIndicator())
                                    : Container(
                                        decoration: BoxDecoration(
                                          gradient: _userType == UserType.tunanetra
                                              ? AppColors.primaryGradient
                                              : AppColors.accentGradient,
                                          borderRadius: BorderRadius.circular(16),
                                          boxShadow: [
                                            BoxShadow(
                                              color: (_userType == UserType.tunanetra
                                                      ? AppColors.primary
                                                      : AppColors.accent)
                                                  .withOpacity(0.4),
                                              blurRadius: 12,
                                              offset: const Offset(0, 6),
                                            ),
                                          ],
                                        ),
                                        child: ElevatedButton(
                                          onPressed: _handleRegister,
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.transparent,
                                            shadowColor: Colors.transparent,
                                            padding: const EdgeInsets.symmetric(vertical: 18),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(16),
                                            ),
                                          ),
                                          child: Text(
                                            'DAFTAR',
                                            style: AppTextStyles.button.copyWith(
                                              fontSize: 18,
                                            ),
                                          ),
                                        ),
                                      ),
                                const SizedBox(height: 20),
                                
                                // Login Link
                                TextButton(
                                  onPressed: () {
                                    Navigator.pop(context);
                                  },
                                  child: Text.rich(
                                    TextSpan(
                                      text: 'Sudah punya akun? ',
                                      style: AppTextStyles.bodyMedium.copyWith(
                                        color: AppColors.textSecondary,
                                      ),
                                      children: [
                                        TextSpan(
                                          text: 'Login',
                                          style: TextStyle(
                                            color: _userType == UserType.tunanetra
                                                ? AppColors.primary
                                                : AppColors.accent,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildModernTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    bool obscureText = false,
    String? semanticLabel,
    Widget? suffixIcon,
  }) {
    return Semantics(
      label: semanticLabel ?? label,
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        obscureText: obscureText,
        style: AppTextStyles.bodyMedium,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.textSecondary,
          ),
          prefixIcon: Icon(icon, color: AppColors.primary),
          suffixIcon: suffixIcon,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(
              color: _userType == UserType.tunanetra
                  ? AppColors.primary
                  : AppColors.accent,
              width: 2,
            ),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: AppColors.error, width: 2),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: AppColors.error, width: 2),
          ),
          filled: true,
          fillColor: AppColors.background,
        ),
        validator: (value) {
          if (value == null || value.isEmpty) {
            return '$label harus diisi';
          }
          return null;
        },
      ),
    );
  }
}
