import 'package:flutter/material.dart';
import '../../utils/constants.dart';
import '../../services/auth_service.dart';
import '../../services/user_service.dart';

class FamilyHomeScreen extends StatefulWidget {
  const FamilyHomeScreen({super.key});

  @override
  State<FamilyHomeScreen> createState() => _FamilyHomeScreenState();
}

class _FamilyHomeScreenState extends State<FamilyHomeScreen> {
  // Dummy data untuk contoh
  final List<Map<String, dynamic>> _connectedUsers = [
    {
      'name': 'Budi Santoso',
      'lastSeen': '5 menit yang lalu',
      'location': 'Jl. Sudirman No. 123, Jakarta',
      'isOnline': true,
      'batteryLevel': 85,
    },
  ];
  String _userName = 'Keluarga';

  @override
  void initState() {
    super.initState();
    _loadUserName();
  }

  Future<void> _loadUserName() async {
    try {
      final authService = AuthService();
      final userService = UserService();
      
      final uid = authService.currentUserId;
      if (uid != null) {
        final user = await userService.getFamilyUser(uid);
        if (user != null && mounted) {
          setState(() {
            _userName = user.name;
          });
        }
      }
    } catch (e) {
      print('❌ Error loading user name: $e');
    }
  }

  void _viewMonitoring(Map<String, dynamic> user) {
    Navigator.pushNamed(context, AppRoutes.familyMonitoring, arguments: user);
  }

  void _navigateToSettings() {
    Navigator.pushNamed(context, AppRoutes.familySettings);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFFFAFBFC),
              AppColors.accent.withOpacity(0.08),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Clean & Elegant Header
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFFD32F2F),
                      const Color(0xFFE53935),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFD32F2F).withOpacity(0.2),
                      blurRadius: 25,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top Row: Title + Settings
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Pantau Keluarga',
                              style: AppTextStyles.heading2.copyWith(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Monitor semua anggota keluarga',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: Colors.white.withOpacity(0.85),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.3),
                              width: 1,
                            ),
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.settings_rounded, size: 24),
                            color: Colors.white,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: _navigateToSettings,
                            tooltip: 'Pengaturan',
                          ),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 20),
                    
                    // User Info Section
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.25),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.25),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.4),
                                width: 1.5,
                              ),
                            ),
                            child: const Icon(
                              Icons.people_rounded,
                              size: 32,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Dipantau oleh',
                                  style: AppTextStyles.bodySmall.copyWith(
                                    color: Colors.white.withOpacity(0.75),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _userName,
                                  style: AppTextStyles.heading3.copyWith(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.25),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.4),
                                width: 1,
                              ),
                            ),
                            child: Text(
                              '${_connectedUsers.length}',
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              
              // User List
              Expanded(
                child: _connectedUsers.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _connectedUsers.length,
                        itemBuilder: (context, index) {
                          return _buildUserCard(_connectedUsers[index]);
                        },
                      ),
              ),
              
              // Add User Button
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: AppColors.accentGradient,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.accent.withOpacity(0.4),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    onPressed: () {
                      _showAddUserDialog();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.person_add_rounded, size: 28, color: Colors.white),
                        const SizedBox(width: 12),
                        Text(
                          'TAMBAH PENGGUNA',
                          style: AppTextStyles.button.copyWith(
                            fontSize: 18,
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

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.all(40.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.white,
                  Colors.white.withOpacity(0.95),
                ],
              ),
              borderRadius: BorderRadius.circular(35),
              boxShadow: [
                BoxShadow(
                  color: AppColors.textSecondary.withOpacity(0.1),
                  blurRadius: 30,
                  offset: const Offset(0, 15),
                ),
              ],
              border: Border.all(
                color: AppColors.textSecondary.withOpacity(0.1),
                width: 1,
              ),
            ),
            child: Icon(
              Icons.person_off_rounded,
              size: 80,
              color: AppColors.textSecondary.withOpacity(0.4),
            ),
          ),
          const SizedBox(height: 30),
          Text(
            'Belum ada pengguna terhubung',
            style: AppTextStyles.heading3.copyWith(
              color: AppColors.textSecondary,
              fontSize: 20,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            'Tambahkan pengguna untuk mulai monitoring',
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.textSecondary.withOpacity(0.7),
              fontSize: 15,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildUserCard(Map<String, dynamic> user) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white,
            Colors.white.withOpacity(0.95),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: (user['isOnline'] ? AppColors.success : AppColors.textSecondary).withOpacity(0.15),
            blurRadius: 25,
            offset: const Offset(0, 12),
          ),
        ],
        border: Border.all(
          color: (user['isOnline'] ? AppColors.success : AppColors.textSecondary).withOpacity(0.3),
          width: 1.5,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _viewMonitoring(user),
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Avatar with gradient
                    Container(
                      width: 70,
                      height: 70,
                      decoration: BoxDecoration(
                        gradient: user['isOnline'] 
                            ? AppColors.successGradient
                            : LinearGradient(
                                colors: [
                                  AppColors.textSecondary.withOpacity(0.7),
                                  AppColors.textSecondary.withOpacity(0.5),
                                ],
                              ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: (user['isOnline'] ? AppColors.success : AppColors.textSecondary).withOpacity(0.3),
                            blurRadius: 15,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.person_rounded,
                        size: 40,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 16),
                    
                    // User Info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user['name'],
                            style: AppTextStyles.heading3.copyWith(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              gradient: user['isOnline']
                                  ? AppColors.successGradient
                                  : LinearGradient(
                                      colors: [
                                        AppColors.textSecondary.withOpacity(0.7),
                                        AppColors.textSecondary.withOpacity(0.5),
                                      ],
                                    ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  user['isOnline'] 
                                      ? Icons.circle 
                                      : Icons.circle_outlined,
                                  size: 10,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  user['isOnline'] ? 'Online' : 'Offline',
                                  style: AppTextStyles.bodyMedium.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    // Battery Indicator
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: (user['batteryLevel'] > 20 
                            ? AppColors.success 
                            : AppColors.error).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.battery_full_rounded,
                            size: 28,
                            color: user['batteryLevel'] > 20 
                                ? AppColors.success 
                                : AppColors.error,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${user['batteryLevel']}%',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: user['batteryLevel'] > 20 
                                  ? AppColors.success 
                                  : AppColors.error,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                
                // Last Seen
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.info.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppColors.info.withOpacity(0.2),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.access_time_rounded,
                        size: 20,
                        color: AppColors.info,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          user['lastSeen'],
                          style: AppTextStyles.bodyMedium.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                
                // Location
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppColors.error.withOpacity(0.2),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.location_on_rounded,
                        size: 20,
                        color: AppColors.error,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          user['location'],
                          style: AppTextStyles.bodyMedium.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                
                // View Details Button
                Container(
                  decoration: BoxDecoration(
                    gradient: AppColors.accentGradient,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.accent.withOpacity(0.3),
                        blurRadius: 15,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => _viewMonitoring(user),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.visibility_rounded,
                          size: 22,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'LIHAT DETAIL',
                          style: AppTextStyles.button.copyWith(
                            fontSize: 16,
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
    );
  }

  void _showAddUserDialog() {
    final emailController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        title: ShaderMask(
          shaderCallback: (bounds) => AppColors.accentGradient.createShader(bounds),
          child: const Text(
            'Tambah Pengguna',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        content: TextField(
          controller: emailController,
          style: AppTextStyles.bodyMedium,
          decoration: InputDecoration(
            labelText: 'Email Pengguna',
            hintText: 'Masukkan email pengguna tunanetra',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                color: AppColors.accent,
                width: 2,
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('BATAL', style: AppTextStyles.bodyMedium),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Pengguna berhasil ditambahkan')),
              );
            },
            child: const Text('TAMBAH'),
          ),
        ],
      ),
    );
  }
}
