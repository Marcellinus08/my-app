# Panduan Instalasi Flutter di Windows

## Persyaratan Sistem
- Windows 10 atau lebih baru (64-bit)
- Minimal 2.5 GB ruang disk (tidak termasuk IDE/tools)
- Git untuk Windows

## Langkah 1: Download Flutter SDK

1. Buka browser dan kunjungi: https://docs.flutter.dev/get-started/install/windows
2. Klik tombol **"Download Flutter SDK"** atau download langsung dari: https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_latest.zip
3. Simpan file zip di folder Downloads

## Langkah 2: Extract Flutter SDK

1. Buat folder untuk Flutter di lokasi yang mudah diakses (JANGAN di `Program Files`):
   ```
   C:\src\flutter
   ```
   atau
   ```
   C:\flutter
   ```

2. Extract file `flutter_windows_latest.zip` ke folder yang sudah dibuat
3. Pastikan path akhir adalah: `C:\src\flutter\bin` atau `C:\flutter\bin`

## Langkah 3: Tambahkan Flutter ke PATH Environment Variable

1. **Buka System Environment Variables:**
   - Tekan `Win + X` → pilih **System**
   - Klik **Advanced system settings** (di sebelah kiri)
   - Klik tombol **Environment Variables**

2. **Edit PATH:**
   - Di bagian **User variables**, cari variabel **Path**
   - Klik **Edit**
   - Klik **New**
   - Tambahkan path ke Flutter bin: `C:\src\flutter\bin`
   - Klik **OK** untuk semua dialog

3. **Restart PowerShell/Terminal** untuk menerapkan perubahan

## Langkah 4: Instal Git (jika belum ada)

1. Download Git dari: https://git-scm.com/download/win
2. Jalankan installer
3. Gunakan pengaturan default selama instalasi
4. Restart terminal setelah instalasi

## Langkah 5: Verifikasi Instalasi Flutter

Buka PowerShell atau Command Prompt baru dan jalankan:

```powershell
flutter --version
```

Jika berhasil, Anda akan melihat informasi versi Flutter.

## Langkah 6: Jalankan Flutter Doctor

Perintah ini akan mengecek semua dependencies yang diperlukan:

```powershell
flutter doctor
```

Output akan menunjukkan status instalasi dan apa yang masih perlu diinstal.

## Langkah 7: Instal Android Studio (untuk Android Development)

### Download dan Instalasi:
1. Download Android Studio dari: https://developer.android.com/studio
2. Jalankan installer
3. Ikuti wizard instalasi dengan pengaturan **Standard**
4. Biarkan installer mendownload Android SDK, platform-tools, dll.

### Setup Android Studio untuk Flutter:
1. Buka Android Studio
2. Pergi ke **File → Settings** (atau tekan `Ctrl+Alt+S`)
3. Pilih **Plugins**
4. Cari dan instal:
   - **Flutter** plugin (akan otomatis menginstal Dart plugin juga)
5. Restart Android Studio

### Setup Android SDK:
1. Di Android Studio, buka **Tools → SDK Manager**
2. Di tab **SDK Platforms**, pastikan terpilih:
   - Android API 33 atau lebih baru
3. Di tab **SDK Tools**, pastikan terpilih:
   - Android SDK Build-Tools
   - Android SDK Command-line Tools
   - Android SDK Platform-Tools
   - Android Emulator
4. Klik **Apply** untuk menginstal

### Terima Android Licenses:
Buka PowerShell dan jalankan:

```powershell
flutter doctor --android-licenses
```

Tekan `y` untuk menerima semua lisensi.

## Langkah 8: Instal Visual Studio Code (Opsional tapi Direkomendasikan)

### Download dan Instalasi:
1. Download VS Code dari: https://code.visualstudio.com/
2. Jalankan installer
3. Pilih opsi "Add to PATH" saat instalasi

### Instal Extension Flutter:
1. Buka VS Code
2. Tekan `Ctrl+Shift+X` untuk membuka Extensions
3. Cari dan instal:
   - **Flutter** (by Dart Code)
   - **Dart** (akan otomatis terinstal dengan Flutter)

## Langkah 9: Setup Emulator Android (Opsional)

### Membuat AVD (Android Virtual Device):
1. Buka Android Studio
2. Klik **Tools → Device Manager**
3. Klik **Create Device**
4. Pilih device (contoh: Pixel 5)
5. Pilih system image (contoh: API 33 - Android 13.0)
6. Download system image jika belum ada
7. Klik **Finish**

### Menjalankan Emulator dari Terminal:
```powershell
flutter emulators
flutter emulators --launch <emulator_id>
```

## Langkah 10: Verifikasi Semua Instalasi

Jalankan perintah berikut untuk memastikan semuanya terinstal dengan benar:

```powershell
flutter doctor -v
```

Output yang ideal:
```
[✓] Flutter (Channel stable, vX.X.X)
[✓] Android toolchain - develop for Android devices
[✓] Chrome - develop for the web
[✓] Visual Studio - develop Windows apps
[✓] Android Studio
[✓] VS Code
[✓] Connected device
[✓] Network resources
```

## Troubleshooting

### Error: 'flutter' tidak dikenali
**Solusi:** PATH belum terset dengan benar. Restart terminal atau tambahkan ulang Flutter ke PATH.

### Error: cmdline-tools component is missing
**Solusi:** 
```powershell
flutter doctor --android-licenses
```
Atau instal Android SDK Command-line Tools dari Android Studio SDK Manager.

### Error: Unable to locate Android SDK
**Solusi:** Set environment variable `ANDROID_HOME`:
1. Tambahkan variabel baru di Environment Variables
2. Nama: `ANDROID_HOME`
3. Value: `C:\Users\<username>\AppData\Local\Android\Sdk`

### Error: Some Android licenses not accepted
**Solusi:**
```powershell
flutter doctor --android-licenses
```
Tekan `y` untuk menerima semua.

## Membuat Project Flutter Pertama

Setelah semua terinstal, buat project Flutter baru:

```powershell
cd "C:\Users\marcellinus geofani\OneDrive\Dokumen\GitHub\my-app"
flutter create .
```

Atau buat di folder baru:
```powershell
flutter create nama_project_baru
cd nama_project_baru
flutter run
```

## Perintah Flutter yang Berguna

```powershell
# Cek versi Flutter
flutter --version

# Cek status instalasi
flutter doctor

# Update Flutter ke versi terbaru
flutter upgrade

# Lihat devices yang tersedia
flutter devices

# Jalankan aplikasi
flutter run

# Build APK untuk Android
flutter build apk

# Build untuk Windows
flutter build windows

# Bersihkan build cache
flutter clean

# Install dependencies
flutter pub get

# Lihat emulator yang tersedia
flutter emulators
```

## Resources Tambahan

- **Dokumentasi Resmi:** https://docs.flutter.dev/
- **Flutter Codelabs:** https://docs.flutter.dev/codelabs
- **Flutter Widget Catalog:** https://docs.flutter.dev/ui/widgets
- **Dart Language Tour:** https://dart.dev/language
- **Flutter Samples:** https://github.com/flutter/samples

---

## Checklist Instalasi

- [ ] Download Flutter SDK
- [ ] Extract ke folder (C:\src\flutter atau C:\flutter)
- [ ] Tambahkan Flutter ke PATH
- [ ] Instal Git
- [ ] Jalankan `flutter --version` (harus berhasil)
- [ ] Jalankan `flutter doctor`
- [ ] Instal Android Studio
- [ ] Instal Flutter plugin di Android Studio
- [ ] Setup Android SDK
- [ ] Jalankan `flutter doctor --android-licenses`
- [ ] Instal VS Code (opsional)
- [ ] Instal Flutter extension di VS Code
- [ ] Buat AVD/Emulator (opsional)
- [ ] Jalankan `flutter doctor -v` (semua checklist hijau)
- [ ] Buat project Flutter pertama

---

**Selamat! Setelah semua langkah selesai, Anda siap untuk mulai mengembangkan aplikasi Flutter!** 🎉
