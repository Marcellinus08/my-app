# CD-4 — Pembaruan Seksi 1.2.1.7 TTS dan STT

> Bagian ini **menggantikan** seluruh seksi 1.2.1.7 pada `CD4_luaran_software.md` dan pada dokumen Word.
> Konten sebelumnya di CD4 perlu diganti karena beberapa hal berubah setelah implementasi selesai.
>
> **Panduan:**
> - 🔄 **GANTI** — Hapus bagian ini di Word, ganti dengan konten tepat di bawah keterangan.
> - 🆕 **TAMBAHKAN** — Tidak ada di Word, tambahkan setelah posisi yang disebutkan.

---

## 1.2.1.7 Text-to-Speech dan Speech-to-Text

Fitur Text-to-Speech (TTS) dan Speech-to-Text (STT) diimplementasikan untuk mendukung aksesibilitas pengguna tunanetra. TTS digunakan agar aplikasi dapat memberikan respons suara, sedangkan STT digunakan agar pengguna dapat memberi perintah melalui suara.

**Tabel 7. Komponen TTS dan STT**

| Komponen | Peran |
|---|---|
| TTSService | Mengubah teks menjadi suara dengan sistem antrian prioritas dan deduplication |
| STTService | Mengubah suara pengguna menjadi teks perintah, terintegrasi dengan TTSService |
| TunaNetraHomeScreen | Mendengarkan perintah seperti membuka navigasi, SOS, cek SmartCane, dan cuaca |
| NavigationScreen | Mendengarkan perintah tujuan, menghentikan navigasi, dan memberi arahan suara |
| `flutter_tts` | Library untuk text-to-speech |
| `speech_to_text` | Library untuk speech-to-text |

---

### TTSService

> 🔄 **GANTI** seluruh paragraf pembuka TTS, enum `TtsPriority`, class `TTSService`, dan fungsi `speak()` di Word dengan versi berikut.

Pada sisi TTS, aplikasi menggunakan sistem priority queue untuk memastikan instruksi penting tidak terlewat dan pesan lama tidak menumpuk. Setiap permintaan bicara memiliki level prioritas, kunci deduplication, dan waktu kedaluwarsa.

```dart
enum TtsPriority { low, normal, navigation, warning, critical }
```

Lima level prioritas digunakan sesuai konteks. `critical` untuk instruksi keselamatan yang harus diucapkan segera. `warning` untuk peringatan obstacle dari sensor. `navigation` untuk instruksi belok. `normal` untuk konfirmasi aksi pengguna. `low` untuk informasi latar yang dapat dilewati jika ada pesan lebih penting.

```dart
class TTSService {
  static final TTSService _instance = TTSService._internal();
  factory TTSService() => _instance;
  TTSService._internal();

  final FlutterTts _tts = FlutterTts();
  final List<_TtsRequest> _queue = [];
  final Map<String, DateTime> _recentlyCompleted = {};

  bool _isInit = false;
  bool _isSttActive = false;
  bool _isProcessing = false;
  int _speechGeneration = 0;
  int _requestSequence = 0;
  _TtsRequest? _currentRequest;

  static void Function(String text)? onSpeechStartHook;
  static void Function(String text)? onSpeechSendHook;
  static void Function(String text)? onTtsStopStartHook;

  Future<void> init() async {
    if (_isInit) return;
    await _tts.setLanguage('id-ID');
    await _tts.setPitch(1.0);
    await _tts.awaitSpeakCompletion(true);
    _tts.setStartHandler(() {
      onSpeechStartHook?.call(_currentRequest?.text ?? '');
    });
    _isInit = true;
  }
}
```

`TTSService` menggunakan pola singleton agar semua bagian aplikasi menggunakan satu antrian terpusat. `_queue` menyimpan daftar permintaan yang menunggu diucapkan. `_recentlyCompleted` menyimpan waktu selesai tiap teks untuk mencegah pengulangan dalam rentang waktu tertentu. `_speechGeneration` adalah counter yang bertambah setiap kali speech diinterupsi, digunakan untuk mendeteksi apakah proses pemrosesan yang sedang berjalan masih relevan. Tiga hook statis dipasang oleh modul pengukuran response time: `onSpeechStartHook` dipanggil saat TTS engine mulai bersuara, `onSpeechSendHook` dipanggil tepat sebelum `_tts.speak()` dipanggil, dan `onTtsStopStartHook` dipanggil tepat sebelum `_tts.stop()` untuk memisahkan overhead stop dari waktu tunggu antrian.

---

```dart
Future<void> speak(
  String text, {
  TtsPriority priority = TtsPriority.normal,
  String? deduplicationKey,
  String? replacementKey,
  Duration? maxAge,
  Duration duplicateWindow = const Duration(seconds: 2),
}) async {
  final normalizedText = text.trim();
  if (normalizedText.isEmpty) return;

  final request = _TtsRequest(
    sequence: _requestSequence++,
    text: normalizedText,
    priority: priority,
    deduplicationKey: deduplicationKey ?? normalizedText.toLowerCase(),
    replacementKey: replacementKey,
    expiresAt: DateTime.now().add(maxAge ?? _defaultMaxAge(priority)),
    duplicateWindow: duplicateWindow,
  );

  _discardExpiredRequests();
  _removeReplacedRequests(request);
  if (_isDuplicate(request)) {
    request.complete();
    return request.done;
  }

  _queue.add(request);
  if (_shouldInterruptCurrent(request)) {
    await _interruptCurrentSpeech();
  }
  _scheduleProcessing();
  return request.done;
}
```

Fungsi `speak()` menerima parameter opsional untuk mengontrol perilaku antrian. `deduplicationKey` mencegah teks yang sama diucapkan dua kali dalam rentang `duplicateWindow`. `replacementKey` memungkinkan pesan baru menggantikan pesan lama yang belum diucapkan dengan kunci yang sama, berguna misalnya saat instruksi obstacle terus diperbarui. `maxAge` menentukan berapa lama request tetap valid sebelum kedaluwarsa dan dibuang. Return value `request.done` adalah `Future<void>` yang selesai ketika teks selesai diucapkan, sehingga pemanggil dapat menggunakan `await` untuk menunggu giliran bicara selesai. Pesan dengan prioritas `critical` atau `warning` dapat menginterupsi pesan yang sedang diucapkan.

---

> 🆕 **TAMBAHKAN** code block dan paragraf berikut setelah penjelasan `speak()`. Ini menjelaskan fungsi `cancelByReplacementKey()` yang belum ada di Word.

```dart
Future<void> cancelByReplacementKey(String replacementKey) async {
  final normalizedKey = replacementKey.trim();
  if (normalizedKey.isEmpty) return;

  for (final request in _queue.where(
    (request) => request.replacementKey == normalizedKey,
  )) {
    request.complete();
  }
  _queue.removeWhere((request) => request.replacementKey == normalizedKey);

  if (_currentRequest?.replacementKey == normalizedKey) {
    await _interruptCurrentSpeech();
  }
}
```

`cancelByReplacementKey()` membatalkan semua permintaan di antrian dengan `replacementKey` tertentu, termasuk yang sedang diucapkan. Fungsi ini digunakan ketika kondisi yang memicu pesan tersebut sudah tidak relevan, misalnya saat navigasi dihentikan dan semua instruksi belok yang sedang menunggu harus dibatalkan.

---

> 🔄 **GANTI** code block `beginSttSession()` dan `endSttSession()` di Word beserta paragraf penjelasannya dengan versi berikut.

```dart
Future<void> beginSttSession() async {
  _isSttActive = true;

  final currentRequest = _currentRequest;
  if (currentRequest != null &&
      _isSafetyPriority(currentRequest.priority) &&
      !currentRequest.isExpired &&
      !_queue.any((request) =>
          request.deduplicationKey == currentRequest.deduplicationKey)) {
    _queue.add(currentRequest.copyForRetry(sequence: _requestSequence++));
  }

  await _interruptCurrentSpeech();
}

void endSttSession() {
  if (!_isSttActive) return;
  _isSttActive = false;
  _scheduleProcessing();
}
```

`beginSttSession()` dipanggil sebelum mikrofon diaktifkan. Sebelum menghentikan TTS, fungsi ini memeriksa apakah pesan yang sedang diucapkan memiliki prioritas safety (`warning` atau `critical`) dan belum kedaluwarsa. Jika ya, pesan tersebut dimasukkan kembali ke antrian (`copyForRetry`) agar tidak hilang. Setelah itu, TTS dihentikan agar suara aplikasi tidak tertangkap sebagai input pengguna. `endSttSession()` dipanggil setelah mikrofon selesai sehingga TTS dapat kembali memproses antrian yang tertunda.

---

### STTService

> 🔄 **GANTI** seluruh code block class `STTService` di Word beserta paragraf penjelasannya dengan versi berikut.

```dart
class STTService {
  static final STTService _instance = STTService._internal();
  factory STTService() => _instance;
  STTService._internal();

  final SpeechToText _stt = SpeechToText();
  bool isListening = false;
  bool _isInitialized = false;
  bool _isStartingListening = false;

  Future<void> startListening(
    Function(String) onResult, {
    SpeechErrorListener? onError,
    SpeechStatusListener? onStatus,
    VoidCallback? onNoSpeechDetected,
    Duration pauseFor = const Duration(seconds: 30),
    bool finalResultsOnly = false,
  }) async {
    final ttsService = TTSService();
    bool hadResult = false;

    try {
      final available = await init(
        onError: (error) {
          isListening = false;
          ttsService.endSttSession();
          onError?.call(error);
        },
        onStatus: (status) {
          isListening = status == 'listening';
          if (!_isStartingListening &&
              (status == 'done' || status == 'notListening')) {
            if (!hadResult) onNoSpeechDetected?.call();
            ttsService.endSttSession();
          }
          onStatus?.call(status);
        },
      );

      if (!available) {
        debugPrint('STT tidak tersedia');
        return;
      }

      _isStartingListening = true;
      if (_stt.isListening || isListening) {
        await _stt.cancel();
        isListening = false;
      }

      await ttsService.speak('Silakan bicara', priority: TtsPriority.critical);
      await ttsService.beginSttSession();
      isListening = true;

      await _stt.listen(
        localeId: 'id_ID',
        listenFor: const Duration(minutes: 5),
        pauseFor: pauseFor,
        onResult: (result) {
          if (finalResultsOnly && !result.finalResult) return;
          hadResult = true;
          onResult(result.recognizedWords);
        },
      );
    } catch (error, stackTrace) {
      isListening = false;
      ttsService.endSttSession();
      debugPrint('Gagal memulai STT: $error');
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      _isStartingListening = false;
    }
  }

  Future<void> stopListening() async {
    try {
      if (_isInitialized) {
        await _stt.cancel();
        isListening = false;
      }
    } finally {
      TTSService().endSttSession();
    }
  }

  Future<void> finishListening() async {
    try {
      if (_isInitialized && _stt.isListening) {
        await _stt.stop();
        isListening = false;
      }
    } finally {
      TTSService().endSttSession();
    }
  }
}
```

`STTService` menggunakan pola singleton. Flag `_isStartingListening` mencegah status callback `done` atau `notListening` yang terpanggil selama proses inisialisasi awal dianggap sebagai sinyal tidak ada suara terdeteksi. Sebelum mikrofon diaktifkan, jika listener lama masih aktif, `_stt.cancel()` dipanggil untuk menghentikannya. TTS kemudian mengucapkan `'Silakan bicara'` dengan prioritas `critical` lalu memanggil `beginSttSession()` untuk memastikan TTS berhenti sepenuhnya sebelum mic aktif. Parameter `pauseFor` mengontrol berapa lama sistem menunggu jeda suara sebelum menganggap pengguna selesai berbicara. Parameter `finalResultsOnly` menghindari pemrosesan hasil sementara. `onNoSpeechDetected` dipanggil jika tidak ada suara yang terdeteksi. `stopListening()` menggunakan `_stt.cancel()` agar pendengar dibatalkan segera tanpa menunggu hasil akhir. `finishListening()` menggunakan `_stt.stop()` untuk menunggu hasil akhir terlebih dahulu sebelum berhenti, digunakan saat pengguna ingin menyelesaikan input secara normal. Keduanya selalu memanggil `endSttSession()` agar TTS dapat kembali aktif.

---

### Integrasi TTS dan STT di Screen

> 🔄 **GANTI** seluruh paragraf dan code block yang membahas `speakSafe()` dan `_handleCommand()` di Word dengan versi berikut.

Setiap screen yang menggunakan TTS mendefinisikan fungsi `speakSafe()` lokal. Fungsi ini melacak status `_isSpeaking` di level screen, yang digunakan sebagai guard untuk mencegah STT dimulai saat TTS masih berbicara.

```dart
Future<void> speakSafe(
  String text, {
  TtsPriority priority = TtsPriority.normal,
  String? deduplicationKey,
  String? replacementKey,
  Duration? maxAge,
}) async {
  _isSpeaking = true;
  try {
    await _ttsService.speak(
      text,
      priority: priority,
      deduplicationKey: deduplicationKey,
      replacementKey: replacementKey,
      maxAge: maxAge,
    );
  } finally {
    _isSpeaking = false;
  }
}
```

`speakSafe()` adalah wrapper tipis di atas `TTSService.speak()`. Flag `_isSpeaking` di level screen digunakan pada `_startListening()` untuk menunda aktivasi mikrofon jika TTS sedang berjalan, sehingga perintah suara tidak dikirim ke STT sebelum giliran bicara TTS selesai.

---

`_handleCommand()` pada `TunaNetraHomeScreen` memroses perintah suara pengguna di halaman utama.

```dart
void _handleCommand(String command) async {
  await _stopHomeStt();

  if (TunaNetraVoiceCommands.isHomeCommand(command)) {
    await speakSafe("Kamu sudah berada di halaman utama");
  } else if (TunaNetraVoiceCommands.isSosCommand(command)) {
    await _triggerEmergency();
  } else if (command.contains("cek cuaca")) {
    await _speakCurrentWeather();
  } else if (_isReconnectSmartCaneCommand(command)) {
    await _reconnectSmartCaneFromVoice();
  } else if (_isConnectSmartCaneCommand(command)) {
    await speakSafe("Membuka koneksi SmartCane");
    await _handleHomeConnectionTap();
  } else if (command.contains("cek koneksi")) {
    await _speakSmartCaneConnectionStatus();
  } else if (command.contains("cek baterai")) {
    await _speakSmartCaneBatteryStatus();
  } else if (_isCheckSmartCaneCommand(command)) {
    await _speakSmartCaneStatus();
  } else if (command.contains("cek gps")) {
    await _speakGpsStatus();
  } else if (command.contains("navigasi")) {
    await speakSafe("Membuka navigasi");
    Navigator.pushNamed(context, AppRoutes.tunaNetraNavigation);
  } else if (command.contains("ebook") || command.contains("buku panduan")) {
    await speakSafe("Membuka buku panduan");
    Navigator.pushNamed(context, AppRoutes.tunaNetraEbook);
  } else if (command.contains("pengaturan")) {
    await speakSafe("Membuka pengaturan");
    Navigator.pushNamed(context, AppRoutes.tunaNetraSettings);
  } else if (TunaNetraVoiceCommands.isPageStatusCommand(command)) {
    await speakSafe("Anda sedang berada di halaman utama");
  } else {
    await speakSafe("Perintah tidak dikenali");
  }
}
```

`_handleCommand()` pada halaman utama menangani sembilan kategori perintah. Perintah navigasi, bluetooth, ebook, dan pengaturan membuka halaman yang sesuai. Perintah SOS memanggil `_triggerEmergency()` langsung. Perintah cek SmartCane menghasilkan laporan status koneksi, baterai, dan sensor secara verbal. Perintah cek cuaca membaca data cuaca terkini. Perintah yang tidak dikenali memberikan konfirmasi verbal agar pengguna mengetahui input tidak berhasil diproses.

---

> 🆕 **TAMBAHKAN** code block dan paragraf berikut setelah penjelasan `_handleCommand()` pada TunaNetraHomeScreen. Ini menjelaskan handler perintah pada NavigationScreen yang belum ada di Word.

`_handleNavigationCommand()` pada `NavigationScreen` memroses perintah suara pengguna saat navigasi aktif.

```dart
Future<void> _handleNavigationCommand(String command) async {
  final cleanedCommand = command.trim();
  if (cleanedCommand.length < 2) return;

  await _stopNavigationStt();

  if (TunaNetraVoiceCommands.isHomeCommand(cleanedCommand)) {
    await speakSafe('Membuka halaman utama');
    Navigator.of(context).pushNamedAndRemoveUntil(
      AppRoutes.tunaNetraHome, (route) => false,
    );
    return;
  }
  if (TunaNetraVoiceCommands.isSosCommand(cleanedCommand)) {
    await _triggerNavigationSos();
    return;
  }
  if (cleanedCommand.contains('hentikan')) {
    if (_isFreeMode) {
      _exitFreeMode();
      await speakSafe('Mode jelajah dihentikan. Kembali ke halaman pilih tempat.');
    } else {
      await speakSafe('Navigasi dihentikan');
      await _endNavigationSession();
    }
    return;
  }
  if (!_isFreeMode && !_isNavigating && cleanedCommand.contains('jelajah')) {
    _enterFreeMode();
    return;
  }

  final matchedPlace = _findPlaceFromCommand(cleanedCommand);
  if (matchedPlace != null) {
    setState(() {
      _selectedPlace = matchedPlace;
      _isLoadingRoute = true;
    });
    await speakSafe('Memilih ${_formatPlaceName(matchedPlace.name)}');
    _startLocationStreaming();
    return;
  }

  await speakSafe(
    'Perintah tidak dikenali. Tekan dan tahan tombol merah untuk mencoba kembali.',
  );
}
```

`_handleNavigationCommand()` menangani perintah yang relevan saat navigasi. Pengguna dapat berpindah ke halaman utama, memicu SOS, menghentikan navigasi aktif, mengaktifkan mode jelajah bebas tanpa tujuan, atau memilih tempat tujuan baru dengan menyebut namanya. `_findPlaceFromCommand()` melakukan pencocokan nama tempat dari daftar tempat yang tersedia. Perintah home menggunakan `pushNamedAndRemoveUntil` untuk menghapus seluruh stack navigasi sehingga pengguna tidak dapat kembali ke halaman navigasi menggunakan tombol back.

---

Luaran modul TTS dan STT adalah interaksi suara dua arah. Pengguna dapat mengontrol sebagian besar fitur tanpa harus melihat layar, sedangkan aplikasi memberikan konfirmasi dan instruksi secara verbal dengan jaminan tidak ada pesan yang saling bertumpuk atau terlewat. Koordinasi antara TTS dan STT ditangani secara otomatis oleh mekanisme `beginSttSession`/`endSttSession` di dalam service, sehingga screen hanya perlu memanggil `startListening()` tanpa perlu mengelola state interlock secara manual.
