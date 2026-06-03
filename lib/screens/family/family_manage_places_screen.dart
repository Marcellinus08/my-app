import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../services/family_place_service.dart';
import '../../utils/constants.dart';
import '../../widgets/app_dialog.dart';

class FamilyManagePlacesScreen extends StatefulWidget {
  final String? ownerUid;
  final String? ownerName;

  const FamilyManagePlacesScreen({super.key, this.ownerUid, this.ownerName});

  @override
  State<FamilyManagePlacesScreen> createState() =>
      _FamilyManagePlacesScreenState();
}

class _FamilyManagePlacesScreenState extends State<FamilyManagePlacesScreen> {
  static const List<String> _categories = [
    'Rumah',
    'Kesehatan',
    'Pendidikan',
    'Ibadah',
    'Transportasi',
    'Belanja',
    'Lainnya',
  ];

  final _service = FamilyPlaceService();
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _gmapLinkController = TextEditingController();

  String? _selectedCategory;
  String? _pairedUserUid;
  bool _isLoading = true;
  bool _isSaving = false;

  TextStyle get _fieldTextStyle => AppTextStyles.bodyLarge.copyWith(
    fontSize: 14,
    color: AppColors.textPrimary,
    fontWeight: FontWeight.w700,
    height: 1.3,
  );

  TextStyle get _fieldHintStyle => AppTextStyles.bodyLarge.copyWith(
    fontSize: 14,
    color: AppColors.textSecondary,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  @override
  void initState() {
    super.initState();
    _loadPairedUser();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _gmapLinkController.dispose();
    super.dispose();
  }

  Future<void> _loadPairedUser() async {
    final ownerUid = widget.ownerUid;
    if (ownerUid != null && ownerUid.isNotEmpty) {
      if (!mounted) return;
      setState(() {
        _pairedUserUid = ownerUid;
        _isLoading = false;
      });
      return;
    }

    final pairedUserUid = await _service.getPairedUserUid();
    if (!mounted) return;
    setState(() {
      _pairedUserUid = pairedUserUid;
      _isLoading = false;
    });
  }

  Future<void> _savePlace() async {
    final ownerUid = _pairedUserUid;
    if (ownerUid == null || ownerUid.isEmpty) return;
    if (_formKey.currentState?.validate() != true) return;

    final coordinates = _service.parseLatLngFromGoogleMapsLink(
      _gmapLinkController.text,
    );
    if (coordinates == null) {
      _showSnackBar(
        'Koordinat tidak ditemukan. Pastikan link Google Maps berisi koordinat lokasi.',
        isError: true,
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      await _service.addPrivatePlace(
        name: _nameController.text,
        address: _addressController.text,
        gmapLink: _gmapLinkController.text,
        category: _selectedCategory!,
        ownerUid: ownerUid,
      );

      _formKey.currentState?.reset();
      _nameController.clear();
      _addressController.clear();
      _gmapLinkController.clear();
      setState(() => _selectedCategory = null);
      _showSnackBar('Tempat berhasil disimpan');
    } catch (e) {
      _showSnackBar(e.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _deletePlace(String placeId) async {
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: 'Hapus tempat?',
      description: 'Tempat yang dihapus tidak dapat dikembalikan.',
      icon: Icons.location_off_rounded,
      iconColor: AppColors.error,
      cancelText: 'Batal',
      confirmText: 'Hapus',
      confirmButtonColor: AppColors.error,
      isDangerous: true,
    );

    if (confirmed != true) return;

    try {
      await _service.deletePlace(placeId);
      _showSnackBar('Tempat berhasil dihapus');
    } catch (e) {
      _showSnackBar('Gagal menghapus tempat', isError: true);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        backgroundColor: isError ? AppColors.error : AppColors.success,
        elevation: 2,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFD),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(child: _buildContent()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: AppColors.textPrimary.withValues(alpha: 0.045),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Material(
            color: AppColors.primaryDark,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: () => Navigator.of(context).maybePop(),
              borderRadius: BorderRadius.circular(12),
              child: const SizedBox(
                width: 42,
                height: 42,
                child: Icon(
                  Icons.arrow_back_rounded,
                  color: Colors.white,
                  size: 23,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Kelola Tempat',
                  style: AppTextStyles.heading2.copyWith(
                    color: AppColors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  _isLoading
                      ? 'Memuat data...'
                      : _pairedUserUid == null || _pairedUserUid!.isEmpty
                      ? 'Belum ada pengguna terhubung'
                      : widget.ownerName == null || widget.ownerName!.isEmpty
                      ? 'Tambah tujuan privat'
                      : 'Tempat privat pengguna',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final pairedUserUid = _pairedUserUid;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (pairedUserUid == null || pairedUserUid.isEmpty) {
      return _buildEmptyPairing();
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFormCard(),
          const SizedBox(height: 22),
          _buildPlacesList(pairedUserUid),
        ],
      ),
    );
  }

  Widget _buildEmptyPairing() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.link_off_rounded,
              size: 56,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 14),
            Text(
              'Belum ada pengguna tuna netra yang terhubung.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Text(
        title,
        style: AppTextStyles.heading3.copyWith(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }

  Widget _buildFormCard() {
    return Container(
      decoration: _cardDecoration(),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.primaryDark.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.add_location_alt_rounded,
                      color: AppColors.primaryDark,
                      size: 23,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Tambah Tempat Privat',
                          style: AppTextStyles.bodyLarge.copyWith(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Simpan tujuan khusus untuk pengguna',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.textSecondary,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _nameController,
                textInputAction: TextInputAction.next,
                style: _fieldTextStyle,
                decoration: _inputDecoration(
                  hintText: 'Nama tempat',
                  prefixIcon: Icons.place_rounded,
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Nama tempat wajib diisi'
                    : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _addressController,
                textInputAction: TextInputAction.next,
                style: _fieldTextStyle,
                decoration: _inputDecoration(
                  hintText: 'Alamat',
                  prefixIcon: Icons.notes_rounded,
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Alamat wajib diisi'
                    : null,
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _selectedCategory,
                style: _fieldTextStyle,
                decoration: _inputDecoration(
                  prefixIcon: Icons.category_rounded,
                ),
                hint: Text('Kategori', style: _fieldHintStyle),
                disabledHint: Text('Kategori', style: _fieldHintStyle),
                items: _categories
                    .map(
                      (category) => DropdownMenuItem(
                        value: category,
                        child: Text(category),
                      ),
                    )
                    .toList(),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Kategori wajib dipilih'
                    : null,
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _selectedCategory = value);
                },
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _gmapLinkController,
                textInputAction: TextInputAction.done,
                style: _fieldTextStyle,
                decoration: _inputDecoration(
                  hintText: 'Link Google Maps',
                  prefixIcon: Icons.link_rounded,
                  helperText: 'Pastikan link berisi koordinat lokasi.',
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Link Google Maps wajib diisi'
                    : null,
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.infoLight.withValues(alpha: 0.46),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFD7EAFB)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      color: AppColors.primaryDark,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Contoh: https://www.google.com/maps?q=-6.977308,107.632249',
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.primaryDark,
                          fontWeight: FontWeight.w700,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: _isSaving ? null : _savePlace,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 180),
                    opacity: _isSaving ? 0.72 : 1,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      decoration: BoxDecoration(
                        color: AppColors.primaryDark,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primaryDark.withValues(
                              alpha: 0.14,
                            ),
                            blurRadius: 12,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (_isSaving)
                            const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          else
                            const Icon(
                              Icons.save_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          const SizedBox(width: 10),
                          Text(
                            _isSaving ? 'Menyimpan...' : 'Simpan Tempat',
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
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

  Widget _buildPlacesList(String ownerUid) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _service.getMyCreatedPlacesStream(ownerUid),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint('Gagal memuat tempat: ${snapshot.error}');
          return const SizedBox.shrink();
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox.shrink();
        }

        final docs = [...snapshot.data?.docs ?? []]
          ..sort((a, b) {
            final aCreatedAt = a.data()['createdAt'];
            final bCreatedAt = b.data()['createdAt'];
            final aDate = aCreatedAt is Timestamp
                ? aCreatedAt.toDate()
                : DateTime.fromMillisecondsSinceEpoch(0);
            final bDate = bCreatedAt is Timestamp
                ? bCreatedAt.toDate()
                : DateTime.fromMillisecondsSinceEpoch(0);
            return bDate.compareTo(aDate);
          });
        if (docs.isEmpty) {
          return const SizedBox.shrink();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle('Tempat yang Dibuat'),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: docs.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final doc = docs[index];
                final data = doc.data();
                final lat = data['lat'];
                final lng = data['lng'];
                final category = data['category']?.toString() ?? 'Lainnya';

                return Card(
                  elevation: 0,
                  margin: EdgeInsets.zero,
                  color: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Container(
                    decoration: _cardDecoration(radius: 16),
                    child: ListTile(
                      dense: true,
                      minLeadingWidth: 42,
                      horizontalTitleGap: 12,
                      contentPadding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                      leading: Container(
                        width: 42,
                        height: 42,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.primaryLight.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          _getCategoryIcon(category),
                          color: AppColors.primaryDark,
                          size: 21,
                        ),
                      ),
                      title: Text(
                        data['name']?.toString() ?? '-',
                        style: AppTextStyles.bodyMedium.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                          fontSize: 15,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              data['address']?.toString() ?? '-',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                                height: 1.2,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${data['category'] ?? 'Lainnya'} • $lat,$lng',
                              style: AppTextStyles.caption.copyWith(
                                color: AppColors.textSecondary,
                                fontSize: 11,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      trailing: IconButton(
                        tooltip: 'Hapus',
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 36,
                          minHeight: 36,
                        ),
                        icon: const Icon(Icons.delete_outline_rounded),
                        color: AppColors.error,
                        onPressed: () => _deletePlace(doc.id),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  InputDecoration _inputDecoration({
    String? hintText,
    required IconData prefixIcon,
    String? helperText,
  }) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(13),
      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
    );

    return InputDecoration(
      hintText: hintText,
      hintStyle: _fieldHintStyle,
      helperText: helperText,
      floatingLabelBehavior: FloatingLabelBehavior.never,
      prefixIcon: Icon(prefixIcon, color: AppColors.primaryDark, size: 19),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: BorderSide(color: AppColors.primaryDark, width: 1.3),
      ),
      errorBorder: border.copyWith(
        borderSide: BorderSide(color: AppColors.error, width: 1.2),
      ),
      focusedErrorBorder: border.copyWith(
        borderSide: BorderSide(color: AppColors.error, width: 1.4),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
    );
  }

  BoxDecoration _cardDecoration({double radius = 18}) {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(radius),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF0F172A).withValues(alpha: 0.045),
          blurRadius: 14,
          offset: const Offset(0, 6),
        ),
      ],
      border: Border.all(color: const Color(0xFFE2E8F0)),
    );
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'Rumah':
        return Icons.home_rounded;
      case 'Kesehatan':
        return Icons.local_hospital_rounded;
      case 'Pendidikan':
        return Icons.school_rounded;
      case 'Ibadah':
        return Icons.mosque_rounded;
      case 'Transportasi':
        return Icons.directions_bus_rounded;
      case 'Belanja':
        return Icons.shopping_bag_rounded;
      default:
        return Icons.place_rounded;
    }
  }
}
