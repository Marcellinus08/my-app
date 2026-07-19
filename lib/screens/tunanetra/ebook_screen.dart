import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/tts_service.dart';
import '../../services/tunanetra_voice_command_service.dart';
import '../../utils/constants.dart';

class _GuideSection {
  final String title;
  final List<String> points;

  const _GuideSection(this.title, this.points);
}

class _GuideTopic {
  final String title;
  final String description;
  final IconData icon;
  final List<_GuideSection> sections;
  final String? safetyNote;

  const _GuideTopic({
    required this.title,
    required this.description,
    required this.icon,
    required this.sections,
    this.safetyNote,
  });
}

const List<_GuideTopic> _guides = [
  _GuideTopic(
    title: 'Mengenal Sistem',
    description: 'Fungsi Teman Arah dan Smart Cane.',
    icon: Icons.accessibility_new_rounded,
    sections: [
      _GuideSection('Teman Arah', [
        'Aplikasi di telepon untuk navigasi suara dan pemantauan oleh keluarga.',
        'Mendukung perintah suara, informasi Smart Cane, dan SOS darurat.',
      ]),
      _GuideSection('Smart Cane', [
        'Tongkat bantu dengan tiga sensor jarak di sisi kiri, tengah, dan kanan.',
        'Memiliki kamera untuk mengenali objek dan dua tombol: daya dan asisten suara.',
        'Mengirim data sensor dan event tombol ke Teman Arah melalui Bluetooth.',
      ]),
    ],
    safetyNote:
        'Teman Arah dan Smart Cane adalah alat bantu, bukan pengganti kewaspadaan.',
  ),
  _GuideTopic(
    title: 'Persiapan',
    description: 'Yang perlu disiapkan sebelum berangkat.',
    icon: Icons.checklist_rounded,
    sections: [
      _GuideSection('Pemeriksaan', [
        'Pastikan baterai Smart Cane dan telepon mencukupi.',
        'Aktifkan Bluetooth, GPS, dan koneksi internet.',
        'Pastikan volume media telepon dapat terdengar.',
        'Berikan izin lokasi, Bluetooth, mikrofon, dan notifikasi saat diminta.',
      ]),
    ],
  ),
  _GuideTopic(
    title: 'Menghubungkan Smart Cane',
    description: 'Sambungkan Smart Cane ke Teman Arah melalui Bluetooth.',
    icon: Icons.bluetooth_rounded,
    sections: [
      _GuideSection('Cara menghubungkan', [
        'Nyalakan Smart Cane dan dekatkan ke telepon.',
        'Buka Teman Arah, pilih menu koneksi, lalu mulai pencarian.',
        'Pilih Smart Cane yang tersedia dan tunggu konfirmasi koneksi.',
        'Teman Arah akan berkata "SmartCane siap digunakan" jika berhasil.',
      ]),
      _GuideSection('Jika koneksi gagal', [
        'Pastikan Smart Cane menyala dan berada di dekat telepon.',
        'Matikan dan nyalakan Bluetooth, lalu coba sambungkan ulang.',
      ]),
    ],
  ),
  _GuideTopic(
    title: 'Memahami Data Sensor',
    description: 'Status dan peringatan yang diberikan Smart Cane.',
    icon: Icons.sensors_rounded,
    sections: [
      _GuideSection('Status perjalanan', [
        'Smart Cane membaca hambatan di sisi kiri, tengah, dan kanan.',
        'Teman Arah menyampaikan status aman, hati-hati, atau bahaya.',
        'Jika ada objek, nama seperti orang atau kendaraan ikut disebutkan.',
        'Arah yang disarankan dibacakan: maju, kiri, kanan, atau berhenti.',
      ]),
    ],
    safetyNote: 'Konfirmasi kondisi nyata menggunakan tongkat sebelum bergerak.',
  ),
  _GuideTopic(
    title: 'Tombol Smart Cane',
    description: 'Cara menggunakan tombol daya, asisten suara, dan SOS.',
    icon: Icons.touch_app_rounded,
    sections: [
      _GuideSection('Tombol hitam - daya', [
        'Tekan sekali untuk menghidupkan Smart Cane.',
        'Tekan sekali lagi untuk mematikan setelah selesai.',
      ]),
      _GuideSection('Tombol merah - asisten suara', [
        'Tekan dan tahan untuk mulai berbicara.',
        'Ucapkan satu perintah dengan singkat dan jelas.',
        'Lepaskan tombol dan tunggu respons Teman Arah.',
      ]),
      _GuideSection('Tombol merah - SOS', [
        'Tekan tombol merah lima kali dengan cepat untuk mengirim SOS.',
        'Dengarkan konfirmasi pengiriman dari Teman Arah.',
      ]),
    ],
  ),
  _GuideTopic(
    title: 'Memeriksa Status',
    description: 'Cek kondisi sistem sebelum dan selama perjalanan.',
    icon: Icons.home_rounded,
    sections: [
      _GuideSection('Perintah cek', [
        '"Cek SmartCane" untuk mengetahui kesiapan alat.',
        '"Cek baterai" untuk memeriksa baterai Smart Cane.',
        '"Cek koneksi" untuk status Bluetooth.',
        '"Cek GPS" untuk status lokasi.',
      ]),
    ],
  ),
  _GuideTopic(
    title: 'Perintah Suara',
    description: 'Daftar perintah suara yang dapat digunakan.',
    icon: Icons.mic_rounded,
    sections: [
      _GuideSection('Perintah global', [
        '"Halaman utama" atau "Beranda" untuk kembali ke halaman utama.',
        '"SOS", "Tolong", atau "Bantuan" untuk mengirim SOS.',
      ]),
      _GuideSection('Di halaman utama', [
        '"Navigasi" untuk membuka halaman navigasi.',
        '"Buku panduan" untuk membuka Buku Panduan.',
        '"Pengaturan" untuk membuka pengaturan.',
        '"Hubungkan SmartCane" untuk membuka menu koneksi.',
        '"Cek cuaca" untuk membacakan informasi cuaca.',
      ]),
      _GuideSection('Di halaman navigasi', [
        'Ucapkan nama atau alamat tujuan untuk memilih destinasi.',
        '"Cek jarak" untuk sisa jarak ke tujuan.',
        '"Cek waktu" untuk estimasi waktu perjalanan.',
        '"Hentikan navigasi" untuk mengakhiri rute.',
      ]),
    ],
  ),
  _GuideTopic(
    title: 'Navigasi',
    description: 'Memulai dan mengikuti rute perjalanan.',
    icon: Icons.navigation_rounded,
    sections: [
      _GuideSection('Memulai', [
        'Pastikan Smart Cane sudah terhubung dan siap.',
        'Buka Navigasi, ucapkan atau pilih tujuan, lalu tunggu rute ditemukan.',
        'Dengarkan instruksi awal sebelum mulai berjalan.',
      ]),
      _GuideSection('Selama perjalanan', [
        'Teman Arah memberi instruksi belokan pada jarak 30, 20, dan 10 meter.',
        'Gunakan Smart Cane untuk meraba batas jalan dan menemukan bukaan belokan.',
        'Jika keluar rute, berhenti dan tunggu Teman Arah menghitung ulang.',
      ]),
    ],
    safetyNote:
        'Posisi GPS dapat bergeser. Utamakan kondisi nyata dan hasil rabaan tongkat.',
  ),
  _GuideTopic(
    title: 'SOS',
    description: 'Mengirim permintaan bantuan darurat.',
    icon: Icons.sos_rounded,
    sections: [
      _GuideSection('Cara mengirim SOS', [
        'Tekan tombol merah Smart Cane lima kali dengan cepat.',
        'Atau gunakan tombol Kirim SOS di aplikasi Teman Arah.',
        'Atau ucapkan "SOS", "Tolong", atau "Bantuan".',
        'Keluarga akan menerima lokasi dan data pengguna.',
      ]),
    ],
    safetyNote:
        'Gunakan SOS hanya saat tersesat, terluka, atau membutuhkan bantuan segera.',
  ),
  _GuideTopic(
    title: 'Pemecahan Masalah',
    description: 'Mengatasi kendala umum saat menggunakan sistem.',
    icon: Icons.build_circle_rounded,
    sections: [
      _GuideSection('Kendala umum', [
        'Smart Cane tidak ditemukan: pastikan alat menyala dan Bluetooth aktif.',
        'Suara tidak terdengar: periksa volume media telepon.',
        'Perintah suara gagal: periksa izin mikrofon dan kurangi kebisingan.',
        'GPS tidak akurat: pindah ke area terbuka dan tunggu posisi stabil.',
        'Rute tidak ditemukan: periksa GPS, internet, dan ketepatan tujuan.',
      ]),
      _GuideSection('Setelah selesai', [
        'Hentikan navigasi dan kembali ke halaman utama.',
        'Matikan Smart Cane dan isi daya jika diperlukan.',
      ]),
    ],
    safetyNote:
        'Teman Arah dan Smart Cane adalah alat bantu, bukan pengganti kewaspadaan.',
  ),
];

// Display order: Mengenal Sistem, Persiapan, Tombol, Menghubungkan,
//   Memeriksa Status, Sensor, Perintah Suara, Navigasi, SOS, Pemecahan Masalah
const List<int> _guideDisplayOrder = [0, 1, 4, 2, 5, 3, 6, 7, 8, 9];

bool _matchesTopicKeyword(String text, int displayIndex) {
  switch (displayIndex) {
    case 0:
      return text.contains('mengenal');
    case 1:
      return text.contains('persiapan');
    case 2:
      return text.contains('tombol') || text.contains('menghidupkan');
    case 3:
      return text.contains('menghubungkan') || text.contains('sambungkan');
    case 4:
      return text.contains('memeriksa') || text.contains('status sistem');
    case 5:
      return text.contains('sensor') || text.contains('memahami data');
    case 6:
      return text.contains('perintah suara') || text.contains('daftar perintah');
    case 7:
      return text.contains('navigasi');
    case 8:
      // Skip SOS keyword to avoid conflict with global SOS command
      return false;
    case 9:
      return text.contains('pemecahan') || text.contains('masalah');
    default:
      return false;
  }
}

class EbookScreen extends StatefulWidget {
  const EbookScreen({super.key});

  @override
  State<EbookScreen> createState() => _EbookScreenState();
}

class _EbookScreenState extends State<EbookScreen>
    with TunaNetraHomeVoiceCommandMixin {
  static const Color _pageBackground = Color(0xFFF7FAFD);
  static const Color _cardBorder = Color(0xFFE2E8F0);

  @override
  void initState() {
    super.initState();
    startHomeVoiceCommandListener(
      openingAnnouncement:
          'Buku Panduan. Sepuluh topik tersedia. Ucapkan Topik 1 hingga Topik 10 untuk membuka topik.',
      pageName: 'Buku Panduan',
      onCommand: _handleVoiceCommand,
    );
  }

  @override
  void dispose() {
    stopHomeVoiceCommandListener();
    super.dispose();
  }

  Future<bool> _handleVoiceCommand(String text) async {
    final index = _getTopicDisplayIndex(text);
    if (index != null) {
      await _navigateToGuide(_guides[_guideDisplayOrder[index]]);
      return true;
    }
    return false;
  }

  int? _getTopicDisplayIndex(String text) {
    const numberWords = [
      'satu',
      'dua',
      'tiga',
      'empat',
      'lima',
      'enam',
      'tujuh',
      'delapan',
      'sembilan',
      'sepuluh',
    ];

    for (var i = 0; i < numberWords.length; i++) {
      if (text.contains('topik ${i + 1}') ||
          text.contains('topik ${numberWords[i]}')) {
        return i;
      }
    }

    for (var i = 0; i < _guideDisplayOrder.length; i++) {
      if (_matchesTopicKeyword(text, i)) return i;
    }

    return null;
  }

  Future<void> _navigateToGuide(_GuideTopic guide) async {
    await stopHomeVoiceCommandListener();
    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => _GuideDetailScreen(guide: guide),
      ),
    );

    if (mounted) {
      startHomeVoiceCommandListener(
        openingAnnouncement: 'Kembali ke daftar topik.',
        onCommand: _handleVoiceCommand,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBackground,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                children: [
                  _buildVoiceHintCard(),
                  const SizedBox(height: 11),
                  ..._guideDisplayOrder.asMap().entries.map(
                    (entry) => _buildGuideItem(
                      entry.key + 1,
                      _guides[entry.value],
                    ),
                  ),
                ],
              ),
            ),
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
        border: Border.all(color: _cardBorder),
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
          Semantics(
            button: true,
            label: 'Kembali',
            child: Material(
            color: AppColors.primaryDark,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: () => Navigator.pop(context),
              borderRadius: BorderRadius.circular(12),
              child: const ExcludeSemantics(
                child: SizedBox(
                width: 48,
                height: 48,
                child: Icon(
                  Icons.arrow_back_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              ),
            ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Buku Panduan',
                  style: AppTextStyles.heading3.copyWith(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${_guides.length} topik panduan',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVoiceHintCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.infoLight.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.infoLight),
      ),
      child: Row(
        children: [
          const Icon(Icons.mic_rounded, color: AppColors.primaryDark, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Ucapkan "Topik 1" hingga "Topik 10" untuk membuka topik.',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textPrimary,
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGuideItem(int number, _GuideTopic guide) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        button: true,
        label: 'Topik $number. ${guide.title}',
        hint: guide.description,
        child: ExcludeSemantics(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _navigateToGuide(guide),
              borderRadius: BorderRadius.circular(14),
              child: Ink(
                padding: const EdgeInsets.symmetric(
                  horizontal: 13,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _cardBorder),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColors.infoLight.withValues(alpha: 0.62),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Icon(
                            guide.icon,
                            color: AppColors.primaryDark,
                            size: 20,
                          ),
                          Positioned(
                            right: 2,
                            bottom: 2,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primaryDark,
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Text(
                                '$number',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  height: 1,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            guide.title,
                            style: AppTextStyles.bodyLarge.copyWith(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              height: 1.22,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            guide.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.textSecondary,
                              fontSize: 12.5,
                              height: 1.32,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.textSecondary,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GuideDetailScreen extends StatefulWidget {
  final _GuideTopic guide;

  const _GuideDetailScreen({required this.guide});

  @override
  State<_GuideDetailScreen> createState() => _GuideDetailScreenState();
}

class _GuideDetailScreenState extends State<_GuideDetailScreen>
    with TunaNetraHomeVoiceCommandMixin {
  static const Color _pageBackground = Color(0xFFF7FAFD);
  static const Color _cardBorder = Color(0xFFE2E8F0);

  final TTSService _ttsService = TTSService();
  bool _isSpeaking = false;

  String get _speechText {
    final parts = <String>[widget.guide.title, widget.guide.description];
    for (final section in widget.guide.sections) {
      parts.add(section.title);
      for (var i = 0; i < section.points.length; i++) {
        parts.add('${i + 1}. ${section.points[i]}');
      }
    }
    if (widget.guide.safetyNote != null) {
      parts.add('Catatan keselamatan. ${widget.guide.safetyNote}');
    }
    return parts.join('. ');
  }

  @override
  void initState() {
    super.initState();
    startHomeVoiceCommandListener(
      openingAnnouncement:
          '${widget.guide.title}. Ucapkan Dengarkan untuk mendengarkan panduan ini.',
      pageName: widget.guide.title,
      onCommand: _handleVoiceCommand,
    );
  }

  @override
  void dispose() {
    stopHomeVoiceCommandListener();
    unawaited(_ttsService.cancelByReplacementKey('ebook-guide'));
    super.dispose();
  }

  Future<bool> _handleVoiceCommand(String text) async {
    if (text.contains('dengarkan') ||
        text.contains('bacakan') ||
        text.contains('baca panduan')) {
      if (!_isSpeaking) await _toggleSpeech();
      return true;
    }
    if (text.contains('berhenti') ||
        text.contains('hentikan') ||
        text.contains('stop')) {
      if (_isSpeaking) await _toggleSpeech();
      await _ttsService.speak(
        'Panduan dihentikan.',
        priority: TtsPriority.normal,
      );
      return true;
    }
    if (text.contains('kembali')) {
      if (!mounted) return true;
      Navigator.pop(context);
      return true;
    }
    return false;
  }

  Future<void> _toggleSpeech() async {
    if (_isSpeaking) {
      await _ttsService.cancelByReplacementKey('ebook-guide');
      if (mounted) setState(() => _isSpeaking = false);
      return;
    }

    setState(() => _isSpeaking = true);
    try {
      await _ttsService.speak(
        _speechText,
        priority: TtsPriority.low,
        replacementKey: 'ebook-guide',
        maxAge: const Duration(minutes: 2),
      );
    } finally {
      if (mounted) setState(() => _isSpeaking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBackground,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 2, 20, 24),
                children: [
                  _buildIntroduction(),
                  const SizedBox(height: 10),
                  for (final section in widget.guide.sections) ...[
                    _buildSection(section),
                    const SizedBox(height: 10),
                  ],
                  if (widget.guide.safetyNote != null) _buildSafetyNote(),
                ],
              ),
            ),
            _buildSpeechButton(),
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
        border: Border.all(color: _cardBorder),
      ),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: 'Kembali',
            child: Material(
            color: AppColors.primaryDark,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: () => Navigator.pop(context),
              borderRadius: BorderRadius.circular(12),
              child: const ExcludeSemantics(
                child: SizedBox(
                width: 48,
                height: 48,
                child: Icon(
                  Icons.arrow_back_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              ),
            ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              widget.guide.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.heading3.copyWith(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                height: 1.2,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIntroduction() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.infoLight.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.infoLight),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(widget.guide.icon, color: AppColors.primaryDark, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              widget.guide.description,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textPrimary,
                fontSize: 14,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(_GuideSection section) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            section.title,
            style: AppTextStyles.bodyLarge.copyWith(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < section.points.length; i++) ...[
            _buildStep(i + 1, section.points[i]),
            if (i != section.points.length - 1) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  Widget _buildStep(int number, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.infoLight,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text(
            '$number',
            style: const TextStyle(
              color: AppColors.primaryDark,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textPrimary,
              fontSize: 14,
              height: 1.4,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSafetyNote() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warningLight.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.34)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.health_and_safety_rounded,
            color: Color(0xFFB45309),
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Catatan Keselamatan',
                  style: TextStyle(
                    color: Color(0xFF92400E),
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.guide.safetyNote!,
                  style: const TextStyle(
                    color: Color(0xFF78350F),
                    fontSize: 13.5,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpeechButton() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: _cardBorder)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton.icon(
            onPressed: _toggleSpeech,
            style: FilledButton.styleFrom(
              backgroundColor:
                  _isSpeaking ? AppColors.error : AppColors.primaryDark,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: Icon(
              _isSpeaking ? Icons.stop_rounded : Icons.volume_up_rounded,
              size: 22,
            ),
            label: Text(
              _isSpeaking ? 'Hentikan Panduan' : 'Dengarkan Panduan',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ),
    );
  }
}
