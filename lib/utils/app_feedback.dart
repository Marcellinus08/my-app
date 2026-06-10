import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'constants.dart';

enum AppFeedbackType { success, error, warning, info }

class AppErrorMessage {
  const AppErrorMessage._();

  static String from(
    Object? error, {
    String fallback = 'Terjadi kendala. Silakan coba lagi.',
  }) {
    if (error == null) return fallback;

    if (error is TimeoutException) {
      return 'Proses membutuhkan waktu terlalu lama. Silakan coba lagi.';
    }
    if (error is SocketException) {
      return 'Koneksi internet bermasalah. Periksa jaringan lalu coba lagi.';
    }

    final code = switch (error) {
      FirebaseAuthException(:final code) => code,
      FirebaseException(:final code) => code,
      _ => '',
    };
    final normalizedCode = code.toLowerCase().replaceAll('_', '-');
    final raw = error.toString().toLowerCase();

    if (_containsAny(normalizedCode, const [
          'invalid-credential',
          'wrong-password',
          'user-not-found',
        ]) ||
        _containsAny(raw, const [
          'invalid-credential',
          'wrong-password',
          'user-not-found',
          'auth credential is incorrect',
          'supplied auth credential',
          'email atau kata sandi tidak sesuai',
          'password salah',
        ])) {
      return 'Email atau kata sandi tidak sesuai.';
    }
    if (raw.contains('password lama salah') ||
        raw.contains('kata sandi lama salah')) {
      return 'Kata sandi lama tidak sesuai.';
    }
    if (_containsAny(normalizedCode, const ['invalid-email']) ||
        raw.contains('format email tidak valid')) {
      return 'Format email belum valid.';
    }
    if (_containsAny(normalizedCode, const ['email-already-in-use']) ||
        raw.contains('email sudah terdaftar')) {
      return 'Email tersebut sudah digunakan oleh akun lain.';
    }
    if (_containsAny(normalizedCode, const ['weak-password']) ||
        raw.contains('password terlalu lemah')) {
      return 'Kata sandi terlalu lemah. Gunakan minimal 6 karakter.';
    }
    if (_containsAny(normalizedCode, const ['user-disabled'])) {
      return 'Akun ini telah dinonaktifkan. Hubungi layanan bantuan.';
    }
    if (_containsAny(normalizedCode, const ['too-many-requests']) ||
        raw.contains('terlalu banyak percobaan')) {
      return 'Terlalu banyak percobaan. Tunggu beberapa saat lalu coba lagi.';
    }
    if (_containsAny(normalizedCode, const ['requires-recent-login']) ||
        raw.contains('requires-recent-login')) {
      return 'Sesi Anda perlu diperbarui. Keluar lalu masuk kembali.';
    }
    if (_containsAny(normalizedCode, const [
          'network-request-failed',
          'unavailable',
        ]) ||
        _containsAny(raw, const [
          'network',
          'socketexception',
          'failed host lookup',
          'connection refused',
          'connection reset',
          'no internet',
          'tidak ada koneksi',
        ])) {
      return 'Koneksi internet bermasalah. Periksa jaringan lalu coba lagi.';
    }
    if (_containsAny(normalizedCode, const [
          'permission-denied',
          'unauthorized',
        ]) ||
        raw.contains('permission-denied')) {
      return 'Akses tidak diizinkan. Periksa akun atau izin aplikasi.';
    }
    if (_containsAny(normalizedCode, const ['not-found']) ||
        raw.contains('akun tidak ditemukan')) {
      return 'Data yang diperlukan tidak ditemukan.';
    }
    if (_containsAny(normalizedCode, const [
          'deadline-exceeded',
          'cancelled',
        ]) ||
        _containsAny(raw, const ['timeout', 'timed out'])) {
      return 'Proses membutuhkan waktu terlalu lama. Silakan coba lagi.';
    }
    if (_containsAny(raw, const [
      'kode pairing tidak valid',
      'kode pairing belum valid',
      'kode pairing sudah digunakan',
    ])) {
      return 'Kode pairing tidak valid atau sudah tidak tersedia.';
    }
    if (raw.contains('email belum diverifikasi')) {
      return 'Email belum diverifikasi. Periksa kotak masuk atau folder spam.';
    }
    if (raw.contains('tipe akun tidak ditemukan')) {
      return 'Data tipe akun tidak ditemukan. Silakan masuk kembali.';
    }

    return fallback;
  }

  static bool _containsAny(String value, List<String> patterns) {
    return patterns.any(value.contains);
  }
}

class AppFeedback {
  const AppFeedback._();

  static void success(
    BuildContext context,
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    show(
      context,
      message,
      type: AppFeedbackType.success,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  static void error(
    BuildContext context,
    Object? error, {
    String fallback = 'Terjadi kendala. Silakan coba lagi.',
  }) {
    show(
      context,
      AppErrorMessage.from(error, fallback: fallback),
      type: AppFeedbackType.error,
    );
  }

  static void warning(
    BuildContext context,
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    show(
      context,
      message,
      type: AppFeedbackType.warning,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  static void info(BuildContext context, String message) {
    show(context, message, type: AppFeedbackType.info);
  }

  static void show(
    BuildContext context,
    String message, {
    AppFeedbackType type = AppFeedbackType.info,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    final style = _styleFor(type);

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(style.icon, color: Colors.white, size: 21),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: style.color,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          elevation: 4,
          duration: Duration(seconds: type == AppFeedbackType.error ? 5 : 3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          action: actionLabel != null && onAction != null
              ? SnackBarAction(
                  label: actionLabel,
                  textColor: Colors.white,
                  onPressed: onAction,
                )
              : null,
        ),
      );
  }

  static ({Color color, IconData icon}) _styleFor(AppFeedbackType type) {
    return switch (type) {
      AppFeedbackType.success => (
        color: const Color(0xFF047857),
        icon: Icons.check_circle_rounded,
      ),
      AppFeedbackType.error => (
        color: const Color(0xFFB91C1C),
        icon: Icons.error_rounded,
      ),
      AppFeedbackType.warning => (
        color: const Color(0xFFB45309),
        icon: Icons.warning_amber_rounded,
      ),
      AppFeedbackType.info => (
        color: AppColors.primaryDark,
        icon: Icons.info_rounded,
      ),
    };
  }
}
