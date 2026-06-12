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
    description:
        'Mengenal fungsi aplikasi, Smart Cane, dan cara keduanya bekerja bersama.',
    icon: Icons.accessibility_new_rounded,
    sections: [
      _GuideSection('Teman Arah', [
        'Teman Arah adalah aplikasi pendamping pada telepon pengguna tunanetra.',
        'Aplikasi menyediakan navigasi suara, informasi Smart Cane, perintah suara, dan SOS darurat.',
        'Teman Arah juga mengirim lokasi perjalanan dan kondisi SOS kepada keluarga yang sudah terhubung.',
      ]),
      _GuideSection('Smart Cane', [
        'Smart Cane adalah tongkat bantu yang membaca kondisi di sekitar pengguna.',
        'Tiga sensor membaca jarak hambatan pada sisi kiri, tengah, dan kanan.',
        'Kamera dan model deteksi membantu mengenali objek di sekitar pengguna.',
        'Tombol pada Smart Cane dapat digunakan untuk mengaktifkan perintah suara dan mengirim SOS.',
      ]),
      _GuideSection('Cara keduanya bekerja bersama', [
        'Smart Cane mengirim data sensor, hasil deteksi objek, baterai, dan event tombol ke aplikasi melalui Bluetooth.',
        'Teman Arah mengolah data tersebut menjadi informasi visual dan suara yang lebih mudah dipahami.',
        'Alat dapat mengirim status aman, hati-hati, atau bahaya.',
        'Model dapat mengirim nama objek dan saran maju, kiri, kanan, atau berhenti.',
        'Saat navigasi aktif, Teman Arah memberikan panduan rute sementara Smart Cane membantu memeriksa kondisi jalan secara langsung.',
      ]),
    ],
    safetyNote:
        'Teman Arah dan Smart Cane merupakan alat bantu. Pengguna tetap perlu meraba jalur dan memperhatikan kondisi lingkungan.',
  ),
  _GuideTopic(
    title: 'Persiapan',
    description:
        'Menyiapkan Smart Cane, aplikasi Teman Arah, telepon, dan koneksi keluarga.',
    icon: Icons.checklist_rounded,
    sections: [
      _GuideSection('Pemeriksaan awal', [
        'Pastikan baterai Smart Cane dan telepon mencukupi.',
        'Nyalakan Smart Cane, telepon, Bluetooth, GPS, dan koneksi internet.',
        'Buka Teman Arah dan tunggu proses izin serta layanan awal selesai.',
        'Pastikan volume media telepon dapat terdengar.',
        'Pastikan akun pengguna sudah terhubung dengan akun keluarga.',
      ]),
      _GuideSection('Izin aplikasi', [
        'Berikan izin lokasi untuk navigasi dan pemantauan keluarga.',
        'Berikan izin Bluetooth untuk menghubungkan Smart Cane.',
        'Berikan izin mikrofon untuk menggunakan perintah suara.',
        'Berikan izin notifikasi untuk menerima informasi penting.',
      ]),
    ],
  ),
  _GuideTopic(
    title: 'Menghubungkan Smart Cane',
    description:
        'Menghubungkan alat ke aplikasi dan mendengarkan tanda sistem siap.',
    icon: Icons.bluetooth_rounded,
    sections: [
      _GuideSection('Koneksi pertama', [
        'Nyalakan Smart Cane dan dekatkan dengan telepon.',
        'Aktifkan Bluetooth, buka Teman Arah, lalu pilih bagian koneksi Smart Cane.',
        'Mulai pencarian dan pilih perangkat Smart Cane yang tersedia.',
        'Teman Arah akan menerima data alat setelah koneksi berhasil.',
      ]),
      _GuideSection('Koneksi ulang', [
        'Aplikasi akan mencoba menyambungkan kembali perangkat yang pernah disimpan.',
        'Jika gagal, pastikan alat menyala, dekatkan ke telepon, lalu buka menu koneksi.',
        'Matikan dan nyalakan Bluetooth jika perangkat tetap tidak ditemukan.',
      ]),
      _GuideSection('Tanda alat siap', [
        'Suara "SmartCane terhubung. Menunggu sistem siap" berarti koneksi Bluetooth berhasil dan sistem alat sedang dipersiapkan.',
        'Smart Cane siap dipakai setelah aplikasi mengatakan "SmartCane siap digunakan".',
      ]),
    ],
  ),
  _GuideTopic(
    title: 'Memahami Data Sensor',
    description:
        'Memahami data Smart Cane yang ditampilkan dan dibacakan oleh aplikasi.',
    icon: Icons.sensors_rounded,
    sections: [
      _GuideSection('Tiga sensor jarak', [
        'Smart Cane membaca jarak hambatan pada sisi kiri, tengah, dan kanan.',
        'Kiri menunjukkan jarak hambatan pada sisi kiri, tengah menunjukkan bagian depan, dan kanan menunjukkan sisi kanan.',
        'Teman Arah menerima data tersebut melalui Bluetooth.',
      ]),
      _GuideSection('Status dan keputusan', [
        'Smart Cane menentukan status berdasarkan data sensor dan model.',
        'Teman Arah menyampaikan status aman, hati-hati, atau bahaya melalui tampilan dan suara.',
        'Jika model mengenali objek saat ada hambatan, nama objek seperti orang, kursi, atau kendaraan ikut disebutkan dalam peringatan.',
        'Keputusan arah ikut dibacakan sebagai maju, pindah ke kiri, pindah ke kanan, atau berhenti.',
        'Setelah peringatan hati-hati atau bahaya, Teman Arah mengatakan "Jalur sudah aman. Silakan lanjutkan perjalanan." ketika kondisi kembali aman dan stabil.',
      ]),
      _GuideSection('Deteksi objek', [
        'Kamera Smart Cane dapat mengenali objek seperti orang, kendaraan, dan benda lain.',
        'Teman Arah menampilkan atau membacakan nama objek bersama peringatan jika tersedia.',
      ]),
    ],
    safetyNote:
        'Selalu konfirmasi kondisi nyata menggunakan tongkat sebelum bergerak atau berbelok.',
  ),
  _GuideTopic(
    title: 'Menghidupkan Smart Cane dan Fungsi Tombol',
    description:
        'Menghidupkan alat, menggunakan asisten suara, dan mengirim SOS.',
    icon: Icons.touch_app_rounded,
    sections: [
      _GuideSection('Tombol hitam untuk daya', [
        'Tekan tombol hitam satu kali untuk menghidupkan Smart Cane.',
        'Tunggu Smart Cane menyala dan Teman Arah mulai melakukan proses koneksi.',
        'Setelah selesai digunakan, tekan tombol hitam satu kali lagi untuk mematikan Smart Cane.',
      ]),
      _GuideSection('Tombol merah untuk asisten suara', [
        'Pastikan Smart Cane sudah terhubung dan Teman Arah telah mengatakan bahwa alat siap digunakan.',
        'Tekan dan tahan tombol merah untuk mengaktifkan STT.',
        'Smart Cane mengirim event mulai mendengarkan kepada Teman Arah.',
        'Tetap tahan tombol merah, lalu ucapkan satu perintah dengan singkat dan jelas.',
        'Lepaskan tombol merah setelah selesai berbicara agar Teman Arah berhenti mendengarkan dan memproses ucapan.',
        'Dengarkan respons Teman Arah sampai selesai sebelum memberikan perintah berikutnya.',
        'Jika perintah tidak dikenali, kurangi kebisingan, tahan kembali tombol merah, lalu ulangi perintah.',
      ]),
      _GuideSection('Tombol SOS', [
        'Tekan tombol merah sebanyak lima kali dengan cepat untuk mengirim SOS.',
        'Smart Cane mengirim event SOS kepada Teman Arah.',
        'Teman Arah mengirim lokasi dan data pendukung kepada keluarga jika tersedia.',
        'Dengarkan konfirmasi Teman Arah apakah SOS berhasil atau gagal dikirim.',
        'Gunakan SOS hanya ketika keadaan darurat dan membutuhkan bantuan segera.',
      ]),
    ],
  ),
  _GuideTopic(
    title: 'Memeriksa Status Sistem',
    description:
        'Mengetahui kondisi Smart Cane dan Teman Arah dari satu halaman.',
    icon: Icons.home_rounded,
    sections: [
      _GuideSection('Informasi yang tersedia', [
        'Teman Arah menampilkan status GPS, koneksi Smart Cane, sensor, dan model.',
        'Aplikasi menerima baterai alat dari Smart Cane dan baterai telepon dari sistem telepon.',
        'Gunakan perintah "Cek SmartCane", "Cek koneksi", "Cek baterai", atau "Cek GPS" untuk mendapatkan informasi status.',
        'Mulai perjalanan setelah Teman Arah menyatakan Smart Cane siap digunakan.',
      ]),
      _GuideSection('Menu utama', [
        'Mulai Navigasi digunakan untuk memilih tujuan dan menjalankan rute.',
        'Kirim SOS digunakan untuk meminta bantuan keluarga.',
        'Buku Panduan berisi petunjuk penggunaan sistem.',
        'Pengaturan digunakan untuk profil, koneksi keluarga, dan pengaturan akun.',
      ]),
    ],
  ),
  _GuideTopic(
    title: 'Perintah Suara',
    description: 'Daftar kalimat suara yang dapat dijalankan oleh Teman Arah.',
    icon: Icons.mic_rounded,
    sections: [
      _GuideSection('Perintah global', [
        '"Halaman utama", "Beranda", atau "Home" untuk kembali ke halaman utama.',
        '"SOS", "Darurat", "Tolong", "Bantuan", atau "Butuh bantuan" untuk mengirim SOS.',
      ]),
      _GuideSection('Perintah halaman utama', [
        '"Navigasi" untuk membuka halaman navigasi.',
        '"Buku panduan" atau "Ebook" untuk membuka Buku Panduan.',
        '"Pengaturan" untuk membuka halaman pengaturan.',
        '"Hubungkan SmartCane", "Hubungkan tongkat", atau "Bluetooth" untuk membuka koneksi alat.',
        '"Cek koneksi" untuk membacakan status koneksi Smart Cane.',
        '"Cek baterai" untuk membacakan baterai Smart Cane.',
        '"Cek SmartCane" atau "Cek tongkat" untuk membacakan kesiapan alat.',
        '"Cek GPS" untuk membacakan status GPS.',
        '"Cek cuaca" untuk membacakan informasi cuaca.',
      ]),
      _GuideSection('Perintah halaman navigasi', [
        'Ucapkan nama, kategori, atau alamat tempat untuk memilih tujuan.',
        '"Cek jarak" untuk membacakan sisa jarak ke tujuan.',
        '"Cek waktu" untuk membacakan estimasi waktu perjalanan.',
        '"Hentikan navigasi" untuk mengakhiri navigasi.',
        '"Halaman utama" untuk kembali ke beranda.',
        '"SOS" atau "Butuh bantuan" untuk mengirim SOS selama navigasi.',
      ]),
    ],
  ),
  _GuideTopic(
    title: 'Navigasi',
    description:
        'Mengikuti rute aplikasi sambil memeriksa jalan menggunakan alat.',
    icon: Icons.navigation_rounded,
    sections: [
      _GuideSection('Memulai navigasi', [
        'Pastikan Smart Cane sudah terhubung dan Teman Arah menyatakan alat siap digunakan.',
        'Buka Navigasi, lalu pilih tujuan melalui layar atau tombol STT pada Smart Cane.',
        'Pastikan nama dan alamat tujuan benar.',
        'Tunggu GPS aktif dan rute berhasil ditemukan.',
        'Dengarkan instruksi awal sebelum mulai berjalan.',
      ]),
      _GuideSection('Informasi perjalanan', [
        'Teman Arah memberi informasi arah pada jarak sekitar 30, 20, dan 10 meter.',
        'Pada jarak sekitar 5 meter, Teman Arah memberi tahu bahwa pengguna memasuki area belok.',
        'Gunakan Smart Cane untuk meraba batas jalan dan menemukan bukaan belokan.',
        'Sensor Smart Cane tetap memberikan informasi hambatan selama pengguna mengikuti rute.',
        'Teman Arah memberi konfirmasi setelah arah gerak menunjukkan belokan berhasil.',
      ]),
      _GuideSection('Keluar rute dan tiba', [
        'Jika keluar rute, kurangi kecepatan dan tunggu aplikasi menghitung rute baru.',
        'Periksa lingkungan menggunakan tongkat sebelum melanjutkan.',
        'Navigasi selesai setelah posisi tiba dikonfirmasi GPS atau pengguna menghentikannya.',
      ]),
    ],
    safetyNote:
        'Posisi GPS dan data peta dapat bergeser. Utamakan kondisi nyata dan hasil rabaan Smart Cane.',
  ),
  _GuideTopic(
    title: 'SOS',
    description:
        'Mengirim bantuan dari alat atau aplikasi serta memantau respons keluarga.',
    icon: Icons.sos_rounded,
    sections: [
      _GuideSection('Cara mengirim SOS', [
        'Tekan tombol merah pada Smart Cane sebanyak lima kali dengan cepat atau gunakan tombol Kirim SOS di Teman Arah.',
        'SOS juga dapat dikirim dengan perintah "SOS", "Darurat", "Tolong", atau "Bantuan".',
        'Dengarkan konfirmasi pengiriman dan tetap berada di tempat aman jika memungkinkan.',
      ]),
      _GuideSection('Data untuk keluarga', [
        'Keluarga dapat menerima nama pengguna, waktu SOS, dan koordinat lokasi.',
        'Teman Arah menyertakan baterai telepon dan data baterai dari Smart Cane jika tersedia.',
        'Keluarga dapat melihat perjalanan, membuka lokasi SOS, dan menandainya sebagai ditangani.',
      ]),
      _GuideSection('Jika SOS gagal', [
        'Periksa koneksi internet dan izin lokasi dan coba kirim kembali.',
      ]),
    ],
    safetyNote:
        'Gunakan SOS ketika tersesat, terluka, terancam, atau membutuhkan bantuan segera.',
  ),
  _GuideTopic(
    title: 'Pemecahan Masalah dan Keselamatan',
    description:
        'Mengatasi kendala Smart Cane, Teman Arah, dan koneksi di antara keduanya.',
    icon: Icons.build_circle_rounded,
    sections: [
      _GuideSection('Kendala Smart Cane', [
        'Jika alat tidak ditemukan, pastikan alat menyala, Bluetooth aktif, dan jaraknya dekat.',
        'Jika sensor belum aktif, tunggu proses alat selesai atau sambungkan ulang.',
        'Jika model belum aktif, pastikan kamera tidak tertutup dan sistem alat sudah siap.',
        'Jika baterai belum terbaca, tunggu data berikutnya atau sambungkan ulang.',
      ]),
      _GuideSection('Kendala aplikasi', [
        'Jika GPS tidak akurat, berpindah ke area terbuka dan tunggu posisi stabil.',
        'Jika suara tidak terdengar, periksa volume media dan perangkat audio.',
        'Jika perintah suara gagal, periksa izin mikrofon dan kurangi kebisingan.',
        'Jika rute tidak ditemukan, periksa GPS, internet, dan tujuan.',
      ]),
      _GuideSection('Keselamatan perjalanan', [
        'Pastikan baterai telepon dan Smart Cane mencukupi.',
        'Gunakan speaker atau headset satu sisi agar lingkungan tetap terdengar.',
        'Berhenti di tempat aman sebelum memeriksa layar telepon.',
        'Jangan hanya bergantung pada GPS atau hasil deteksi kamera.',
        'Berhenti jika panduan aplikasi berbeda dengan kondisi nyata.',
      ]),
      _GuideSection('Setelah selesai digunakan', [
        'Pastikan navigasi sudah dihentikan dan kembali ke halaman utama.',
        'Putuskan koneksi jika Smart Cane tidak akan digunakan lagi.',
        'Matikan Smart Cane, lalu isi daya alat dan telepon jika diperlukan.',
        'Simpan Smart Cane di tempat yang aman dan kering.',
      ]),
    ],
    safetyNote:
        'Teman Arah dan Smart Cane adalah alat bantu, bukan pengganti kewaspadaan serta teknik orientasi dan mobilitas.',
  ),
];

const List<int> _guideDisplayOrder = [0, 1, 4, 2, 5, 3, 6, 7, 8, 9];

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
      openingAnnouncement: 'Halaman buku panduan dibuka',
    );
  }

  @override
  void dispose() {
    stopHomeVoiceCommandListener();
    super.dispose();
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
                  _buildInfoCard(),
                  const SizedBox(height: 11),
                  ..._guideDisplayOrder.map(
                    (index) => _buildGuideItem(_guides[index]),
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
          Material(
            color: AppColors.primaryDark,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: () => Navigator.pop(context),
              borderRadius: BorderRadius.circular(12),
              child: const SizedBox(
                width: 48,
                height: 48,
                child: Icon(
                  Icons.arrow_back_rounded,
                  color: Colors.white,
                  size: 24,
                  semanticLabel: 'Kembali',
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

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.infoLight.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.infoLight),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: AppColors.primaryDark,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Ikuti panduan dari persiapan Smart Cane hingga penggunaan aplikasi.',
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

  Widget _buildGuideItem(_GuideTopic guide) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        button: true,
        label: guide.title,
        hint: guide.description,
        child: ExcludeSemantics(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () async {
                await stopHomeVoiceCommandListener();
                if (!mounted) return;

                await Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => _GuideDetailScreen(guide: guide),
                  ),
                );

                if (mounted) {
                  startHomeVoiceCommandListener();
                }
              },
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
                      child: Icon(
                        guide.icon,
                        color: AppColors.primaryDark,
                        size: 21,
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
                          const SizedBox(height: 4),
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

class _GuideDetailScreenState extends State<_GuideDetailScreen> {
  static const Color _pageBackground = Color(0xFFF7FAFD);
  static const Color _cardBorder = Color(0xFFE2E8F0);

  final TTSService _ttsService = TTSService();
  bool _isSpeaking = false;

  String get _speechText {
    final parts = <String>[widget.guide.title, widget.guide.description];
    for (final section in widget.guide.sections) {
      parts.add(section.title);
      for (var index = 0; index < section.points.length; index++) {
        parts.add('Langkah ${index + 1}. ${section.points[index]}');
      }
    }
    if (widget.guide.safetyNote != null) {
      parts.add('Catatan keselamatan. ${widget.guide.safetyNote}');
    }
    return parts.join('. ');
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
  void dispose() {
    unawaited(_ttsService.cancelByReplacementKey('ebook-guide'));
    super.dispose();
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
                  const SizedBox(height: 12),
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
          Material(
            color: AppColors.primaryDark,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: () => Navigator.pop(context),
              borderRadius: BorderRadius.circular(12),
              child: const SizedBox(
                width: 48,
                height: 48,
                child: Icon(
                  Icons.arrow_back_rounded,
                  color: Colors.white,
                  size: 24,
                  semanticLabel: 'Kembali',
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.infoLight.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.infoLight),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(widget.guide.icon, color: AppColors.primaryDark, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              widget.guide.description,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textPrimary,
                fontSize: 14,
                height: 1.45,
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
      padding: const EdgeInsets.all(16),
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
              fontSize: 17,
              fontWeight: FontWeight.w800,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 13),
          for (var index = 0; index < section.points.length; index++) ...[
            _buildStep(index + 1, section.points[index]),
            if (index != section.points.length - 1) const SizedBox(height: 12),
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
          width: 27,
          height: 27,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.infoLight,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '$number',
            style: const TextStyle(
              color: AppColors.primaryDark,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Text(
            text,
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textPrimary,
              fontSize: 14,
              height: 1.45,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSafetyNote() {
    return Container(
      padding: const EdgeInsets.all(15),
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
            size: 23,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Catatan Keselamatan',
                  style: TextStyle(
                    color: Color(0xFF92400E),
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  widget.guide.safetyNote!,
                  style: const TextStyle(
                    color: Color(0xFF78350F),
                    fontSize: 13.5,
                    height: 1.42,
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
              backgroundColor: _isSpeaking
                  ? AppColors.error
                  : AppColors.primaryDark,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: Icon(
              _isSpeaking ? Icons.stop_rounded : Icons.volume_up_rounded,
              size: 23,
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
