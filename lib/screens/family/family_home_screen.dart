import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/family_location_model.dart';
import '../../services/family_location_service.dart';
import '../../services/analytics_service.dart';
import '../../services/auth_service.dart';
import '../../services/notification_service.dart';
import '../../services/pairing_service.dart';
import '../../services/user_service.dart';
import '../../utils/constants.dart';
import 'family_history_screen.dart';
import 'family_manage_places_screen.dart';
import 'family_settings_screen.dart';

class FamilyHomeScreen extends StatefulWidget {
  final String?
  targetUid; // uid of the tunaNetra user to monitor (optional for backward compatibility)
  final String familyId;
  final Map<String, dynamic>? initialSosData;

  const FamilyHomeScreen({
    super.key,
    this.targetUid,
    required this.familyId,
    this.initialSosData,
  });

  @override
  State<FamilyHomeScreen> createState() => _FamilyHomeScreenState();
}

class _FamilyHomeScreenState extends State<FamilyHomeScreen>
    with TickerProviderStateMixin {
  final FamilyLocationService _locationService = FamilyLocationService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final PairingService _pairingService = PairingService();

  // List of monitored users
  List<Map<String, dynamic>> _monitoredUsers = [];
  Map<String, FamilyLocation?> _latestLocations = {};
  Map<String, StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?>
  _userProfileSubscriptions = {};
  Map<String, Map<String, dynamic>?> _liveTrackingData = {};
  Map<String, StreamSubscription<Map<String, dynamic>?>?>
  _liveTrackingSubscriptions = {};
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _activeSosSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _pairingRequestSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _familyDocSub;
  DocumentSnapshot<Map<String, dynamic>>? _activeSosDoc;
  Map<String, dynamic>? _activeSosData;
  final Set<String> _handledPairingRequestIds = {};
  String? _lastNotifiedSosId;
  bool _hasLoadedFamilyDocSnapshot = false;

  String _familyName = 'Keluarga';
  bool _isLoadingUsers = true;
  bool _isSubmittingPairingRequest = false;
  String _resolvedFamilyId = '';

  Timer? _liveTrackingFreshnessTimer;
  DateTime _liveTrackingNow = DateTime.now();
  late Animation<double> _fadeAnimation;
  late AnimationController _fadeController;

  @override
  void initState() {
    super.initState();
    _activeSosData = widget.initialSosData;
    _initializeAnimations();
    AnalyticsService().logScreenView(screenName: 'FamilyHome');
    NotificationService.instance.initializeForFamilyUser();
    _loadMonitoredUsers();
    _subscribeToFamilyConnectionChanges();
    _subscribeToPairingRequestUpdates();
    _subscribeToActiveSos();
    _liveTrackingFreshnessTimer = Timer.periodic(const Duration(seconds: 1), (
      _,
    ) {
      if (mounted) {
        setState(() {
          _liveTrackingNow = DateTime.now();
          // Rebuild status and battery when live_tracking updatedAt becomes stale.
        });
      }
    });
  }

  void _initializeAnimations() {
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeOut));

    _fadeController.forward();
  }

  Future<void> _loadMonitoredUsers() async {
    try {
      final resolvedFamilyId = widget.familyId.trim().isNotEmpty
          ? widget.familyId.trim()
          : (AuthService().currentUserId ?? '');

      _resolvedFamilyId = resolvedFamilyId;

      if (resolvedFamilyId.isEmpty) {
        throw Exception('Family ID kosong - user belum terautentikasi');
      }

      // Use the NEW correct method that uses pairedUserUid
      final userService = UserService();
      final users = await userService.getTunaNetraUsersByFamilyId(
        resolvedFamilyId,
      );

      if (mounted) {
        final activeUids = users
            .map((user) => user['uid'])
            .whereType<String>()
            .where((uid) => uid.isNotEmpty)
            .toSet();

        for (final uid in _userProfileSubscriptions.keys.toList()) {
          if (!activeUids.contains(uid)) {
            _userProfileSubscriptions.remove(uid)?.cancel();
          }
        }

        for (final uid in _liveTrackingSubscriptions.keys.toList()) {
          if (!activeUids.contains(uid)) {
            _liveTrackingSubscriptions.remove(uid)?.cancel();
            _liveTrackingData.remove(uid);
          }
        }

        setState(() {
          _monitoredUsers = users;
          _isLoadingUsers = false;

        });
      }

      // Start listening to each user's location
      for (var user in users) {
        final uid = user['uid'] as String?;
        if (uid != null && uid.isNotEmpty) {
          _subscribeToUserProfile(uid);
          _subscribeToLiveTracking(uid);
        }
      }

    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingUsers = false;
        });
      }
    }
  }

  void _subscribeToLiveTracking(String uid) {
    if (_liveTrackingSubscriptions[uid] != null) {
      _liveTrackingSubscriptions[uid]?.cancel();
    }

    final sub = _locationService
        .watchLiveTracking(uid)
        .listen(
          (data) {
            if (mounted) {
              setState(() {
                _liveTrackingData[uid] = data;
                _latestLocations[uid] = data == null
                    ? null
                    : FamilyLocation.fromMap(uid, data);
              });
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            debugPrint(
              '[FamilyHome] Live tracking listener gagal untuk $uid: $error',
            );
            Future<void>.delayed(const Duration(seconds: 2), () {
              if (!mounted ||
                  !_monitoredUsers.any((user) => user['uid'] == uid)) {
                return;
              }
              _subscribeToLiveTracking(uid);
            });
          },
        );

    _liveTrackingSubscriptions[uid] = sub;
  }

  void _subscribeToUserProfile(String uid) {
    if (_userProfileSubscriptions[uid] != null) {
      _userProfileSubscriptions[uid]?.cancel();
    }

    final sub = _firestore.collection('users').doc(uid).snapshots().listen((
      snapshot,
    ) {
      if (!mounted || !snapshot.exists) return;

      final data = snapshot.data();
      if (data == null) return;

      final newName = _readString(data['name']);
      final newEmail = _readString(data['email']);
      final newPhone = _readString(data['phoneNumber']);

      if (newName == null && newEmail == null && newPhone == null) return;

      var shouldUpdate = false;
      final updatedUsers = _monitoredUsers.map((user) {
        if ((user['uid'] as String?) != uid) return user;

        final updatedUser = Map<String, dynamic>.from(user);
        if (newName != null && updatedUser['name'] != newName) {
          updatedUser['name'] = newName;
          shouldUpdate = true;
        }
        if (newEmail != null && updatedUser['email'] != newEmail) {
          updatedUser['email'] = newEmail;
          shouldUpdate = true;
        }
        if (newPhone != null && updatedUser['phoneNumber'] != newPhone) {
          updatedUser['phoneNumber'] = newPhone;
          shouldUpdate = true;
        }

        return updatedUser;
      }).toList();

      if (!shouldUpdate) return;

      setState(() {
        _monitoredUsers = updatedUsers;
      });
    });

    _userProfileSubscriptions[uid] = sub;
  }

  void _subscribeToActiveSos() {
    final familyId = _currentFamilyId();

    if (familyId.isEmpty) {
      debugPrint('[FamilyHome] Skip SOS listener, familyId empty');
      return;
    }

    _resolvedFamilyId = familyId;
    _activeSosSubscription?.cancel();
    _activeSosSubscription = _firestore
        .collection('sos_alerts')
        .where('familyUids', arrayContains: familyId)
        .snapshots()
        .listen(
          (snapshot) {
            if (!mounted) return;
            final activeDoc = _latestActiveSosDoc(snapshot.docs);
            Map<String, dynamic>? activeData;

            if (activeDoc != null) {
              final docData = activeDoc.data();
              if (docData != null) {
                activeData = {
                  ...docData,
                  'type': 'sos',
                  'sosId': activeDoc.id,
                  'familyUid': familyId,
                };
              }
            }

            setState(() {
              _activeSosDoc = activeDoc;
              _activeSosData = activeData;
            });

            if (activeDoc != null && activeData != null) {
              NotificationService.instance.stopSosAlarmLoop();
              _notifyActiveSos(activeDoc.id, activeData);
            } else {
              _lastNotifiedSosId = null;
            }
          },
          onError: (Object error) {
            debugPrint('[FamilyHome] Active SOS listener error: $error');
          },
        );
  }

  String _currentFamilyId() {
    final authFamilyId = AuthService().currentUserId?.trim() ?? '';
    if (authFamilyId.isNotEmpty) return authFamilyId;

    final resolvedFamilyId = _resolvedFamilyId.trim();
    if (resolvedFamilyId.isNotEmpty) return resolvedFamilyId;

    return widget.familyId.trim();
  }

  DocumentSnapshot<Map<String, dynamic>>? _latestActiveSosDoc(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final activeDocs = docs.where((doc) => doc.data()['status'] == 'active');
    DocumentSnapshot<Map<String, dynamic>>? latestDoc;
    var latestMillis = -1;

    for (final doc in activeDocs) {
      final createdAt = _parseTimestamp(doc.data()['createdAt']);
      final millis = createdAt?.toDate().millisecondsSinceEpoch ?? 0;
      if (latestDoc == null || millis > latestMillis) {
        latestDoc = doc;
        latestMillis = millis;
      }
    }

    return latestDoc;
  }

  void _notifyActiveSos(String sosId, Map<String, dynamic> data) {
    if (_lastNotifiedSosId == sosId) return;
    _lastNotifiedSosId = sosId;

    NotificationService.instance.stopSosAlarmLoop(cancelNotification: true);
    unawaited(NotificationService.instance.showSosOneShotNotification(data));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final userName = _readString(data['userName']) ?? 'Pengguna';
      _showSnackBar(
        'SOS Darurat: $userName membutuhkan bantuan segera.',
        AppColors.error,
      );
    });
  }

  void _subscribeToFamilyConnectionChanges() {
    final familyId = widget.familyId.trim().isNotEmpty
        ? widget.familyId.trim()
        : (AuthService().currentUserId ?? '');

    if (familyId.isEmpty) {
      debugPrint(
        '[FamilyHome] Skip family connection listener, familyId empty',
      );
      return;
    }

    _familyDocSub?.cancel();
    _familyDocSub = _firestore
        .collection('users')
        .doc(familyId)
        .snapshots()
        .listen(
          (snapshot) {
            if (!mounted) return;

            final familyData = snapshot.data();
            final familyName = _readString(familyData?['name']);
            if (familyName != null && familyName != _familyName) {
              setState(() {
                _familyName = familyName;
              });
            }

            if (!_hasLoadedFamilyDocSnapshot) {
              _hasLoadedFamilyDocSnapshot = true;
              return;
            }

            _loadMonitoredUsers();
          },
          onError: (error) {
            debugPrint('[FamilyHome] Family connection listener error: $error');
          },
        );
  }

  bool _isUserOnline(String uid) {
    final liveData = _liveTrackingData[uid];
    if (liveData == null) return false;

    final connectionStatus = liveData['connectionStatus'];
    final gpsStatus = liveData['gpsStatus'];
    final updatedAt = _parseTimestamp(liveData['updatedAt']);

    return connectionStatus == 'online' &&
        gpsStatus == 'gps_live' &&
        _isLiveTrackingFresh(updatedAt);
  }

  double? _getLiveBatteryLevel(String uid) {
    if (!_isUserOnline(uid)) return null;
    return _parseBatteryLevel(_liveTrackingData[uid]?['batteryLevel']);
  }

  double? _getLiveSmartCaneBatteryLevel(String uid) {
    if (!_isUserOnline(uid)) return null;
    return _parseBatteryLevel(_liveTrackingData[uid]?['smartCaneBatteryLevel']);
  }

  Color _getBatteryColor(double battery) {
    if (battery >= 50) {
      return Colors.green;
    } else if (battery >= 20) {
      return Colors.amber;
    } else {
      return Colors.red;
    }
  }

  Future<void> _onAddUserPressed() async {
    var pairingCodeInput = '';

    final pairingCode = await showDialog<String>(
      context: context,
      barrierColor: const Color.fromRGBO(15, 23, 42, 0.4),
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20),
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          actionsPadding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFFE2E8F0), width: 1),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.person_add_rounded,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Tambah Pengguna',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyLarge.copyWith(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Masukkan kode pairing dari akun pengguna tunanetra.',
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
                decoration: InputDecoration(
                  labelText: 'Kode pairing',
                  hintText: 'Contoh: ABC123',
                  labelStyle: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                  hintStyle: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textTertiary,
                    fontWeight: FontWeight.w600,
                  ),
                  prefixIcon: const Icon(
                    Icons.vpn_key_rounded,
                    color: AppColors.primary,
                    size: 18,
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                      color: AppColors.primary,
                      width: 1.2,
                    ),
                  ),
                ),
                onChanged: (value) {
                  pairingCodeInput = value;
                },
                onSubmitted: (_) {
                  Navigator.pop(dialogContext, pairingCodeInput.trim());
                },
              ),
            ],
          ),
          actions: [
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () {
                      FocusScope.of(dialogContext).unfocus();
                      Navigator.pop(dialogContext);
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(
                      'Batal',
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      FocusScope.of(dialogContext).unfocus();
                      Navigator.pop(dialogContext, pairingCodeInput.trim());
                    },
                    icon: const Icon(Icons.send_rounded, size: 16),
                    label: const Text('Kirim'),
                    style: ElevatedButton.styleFrom(
                      elevation: 0,
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      textStyle: AppTextStyles.bodyMedium.copyWith(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );

    if (pairingCode == null) return;
    final normalizedCode = pairingCode.toUpperCase().trim();
    if (normalizedCode.length < 4) {
      _showSnackBar('Kode pairing belum valid', Colors.orange);
      return;
    }

    await _sendPairingRequest(normalizedCode);
  }

  void _subscribeToPairingRequestUpdates() {
    final familyId = widget.familyId.trim().isNotEmpty
        ? widget.familyId.trim()
        : (AuthService().currentUserId ?? '');

    if (familyId.isEmpty) return;

    _pairingRequestSub?.cancel();
    _pairingRequestSub = _firestore
        .collection('pairing_requests')
        .where('familyUid', isEqualTo: familyId)
        .snapshots()
        .listen(
          (snapshot) {
            if (!mounted) return;

            for (final change in snapshot.docChanges) {
              if (change.type != DocumentChangeType.modified) continue;

              final doc = change.doc;
              if (_handledPairingRequestIds.contains(doc.id)) continue;
              final data = doc.data();
              if (data == null) continue;
              final status = data['status'] as String?;

              if (status == 'accepted') {
                _handledPairingRequestIds.add(doc.id);
                _loadMonitoredUsers();
                _showSnackBar(
                  'Permintaan diterima. Pengguna terhubung.',
                  Colors.green,
                );
              } else if (status == 'rejected') {
                _handledPairingRequestIds.add(doc.id);
                _showSnackBar('Permintaan koneksi ditolak.', Colors.orange);
              }
            }
          },
          onError: (error) {
            debugPrint('[FamilyHome] Pairing request listener error: $error');
          },
        );
  }

  Future<void> _sendPairingRequest(String pairingCode) async {
    if (_isSubmittingPairingRequest) return;

    final familyId = _resolvedFamilyId.isNotEmpty
        ? _resolvedFamilyId
        : (widget.familyId.trim().isNotEmpty
              ? widget.familyId.trim()
              : (AuthService().currentUserId ?? ''));

    if (familyId.isEmpty) {
      _showSnackBar('Akun keluarga belum terdeteksi', Colors.red);
      return;
    }

    setState(() {
      _isSubmittingPairingRequest = true;
    });

    try {
      await _pairingService.createPairingRequest(
        familyUid: familyId,
        pairingCode: pairingCode,
      );
      if (!mounted) return;
      _showSnackBar(
        'Permintaan terkirim. Menunggu konfirmasi TunaNetra.',
        Colors.green,
      );
    } on PairingException catch (e) {
      if (!mounted) return;
      _showSnackBar(e.message, const Color(0xFFDC2626));
    } catch (e) {
      if (!mounted) return;
      _showSnackBar(
        'Terjadi kendala saat mengirim permintaan. Silakan coba lagi.',
        const Color(0xFFDC2626),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSubmittingPairingRequest = false;
        });
      }
    }
  }

  void _showSnackBar(String message, Color color) {
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
        backgroundColor: color,
        elevation: 2,
      ),
    );
  }

  Future<void> _openSosLocation() async {
    final userId =
        _readString(_activeSosData?['userId']) ??
        _readString(widget.initialSosData?['userId']) ??
        widget.targetUid ??
        '';

    if (userId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Lokasi SOS belum tersedia',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          backgroundColor: Colors.orange,
          elevation: 2,
        ),
      );
      return;
    }

    final didResolveSos = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (ctx) => FamilyHistoryScreen(
          targetUid: userId,
          familyId: _resolvedFamilyId,
          initialSosData: _activeSosData,
        ),
      ),
    );

    if (!mounted) return;
    if (didResolveSos == true) {
      setState(() {
        _activeSosDoc = null;
        _activeSosData = null;
        _lastNotifiedSosId = null;
      });
    }
    await _refreshActiveSosOnce();
  }

  Future<void> _refreshActiveSosOnce() async {
    final familyId = _currentFamilyId();

    if (familyId.isEmpty) return;

    try {
      final snapshot = await _firestore
          .collection('sos_alerts')
          .where('familyUids', arrayContains: familyId)
          .get(const GetOptions(source: Source.server));

      if (!mounted) return;

      final activeDoc = _latestActiveSosDoc(snapshot.docs);
      if (activeDoc == null) {
        setState(() {
          _activeSosDoc = null;
          _activeSosData = null;
        });
        return;
      }

      final docData = activeDoc.data();
      if (docData == null) {
        return;
      }

      final activeData = {
        ...docData,
        'type': 'sos',
        'sosId': activeDoc.id,
        'familyUid': familyId,
      };

      setState(() {
        _activeSosDoc = activeDoc;
        _activeSosData = activeData;
      });

      NotificationService.instance.stopSosAlarmLoop();
    } catch (error) {
      debugPrint('[FamilyHome] Refresh active SOS failed: $error');
    }
  }

  Future<void> resolveSosAlert() async {
    try {
      final doc = _activeSosDoc;
      if (doc == null) {
        await _resolveLatestSosAlertFallback();
      } else {
        await doc.reference.update({
          'status': 'resolved',
          'resolvedAt': FieldValue.serverTimestamp(),
        });
      }

      debugPrint('[FamilyHome] SOS resolved');
      NotificationService.instance.stopSosAlarmLoop();
      if (!mounted) return;
      setState(() {
        _activeSosDoc = null;
        _activeSosData = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'SOS ditandai sebagai ditangani',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          backgroundColor: Colors.green,
          elevation: 2,
        ),
      );
    } catch (e) {
      debugPrint('[FamilyHome] Resolve SOS failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Gagal menandai SOS',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          backgroundColor: Color(0xFFDC2626),
          elevation: 2,
        ),
      );
    }
  }

  Future<void> _resolveLatestSosAlertFallback() async {
    final familyId = _currentFamilyId();
    if (familyId.isEmpty) {
      throw Exception('Family UID kosong');
    }

    final userId = _readString(_activeSosData?['userId']);
    final snapshot = await _firestore
        .collection('sos_alerts')
        .where('familyUids', arrayContains: familyId)
        .get();

    final docs = userId == null
        ? snapshot.docs
        : snapshot.docs.where((doc) => doc.data()['userId'] == userId).toList();
    final activeDoc = _latestActiveSosDoc(docs);
    if (activeDoc == null) {
      throw Exception('SOS aktif tidak ditemukan');
    }

    await activeDoc.reference.update({
      'status': 'resolved',
      'resolvedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  void dispose() {
    for (var sub in _userProfileSubscriptions.values) {
      sub?.cancel();
    }
    for (var sub in _liveTrackingSubscriptions.values) {
      sub?.cancel();
    }
    _activeSosSubscription?.cancel();
    _pairingRequestSub?.cancel();
    _familyDocSub?.cancel();
    _liveTrackingFreshnessTimer?.cancel();
    _fadeController.dispose();
    _locationService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFD),
      body: FadeTransition(opacity: _fadeAnimation, child: _buildMainContent()),
    );
  }

  Widget _buildMainContent() {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 18),
            _buildFamilyOverviewCard(),
            const SizedBox(height: 14),
            _buildAddUserAction(),
            if (_activeSosData != null) ...[
              const SizedBox(height: 14),
              _buildActiveSosBanner(),
            ],
            const SizedBox(height: 18),
            Text(
              'Pengguna Dipantau',
              style: AppTextStyles.bodyLarge.copyWith(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            if (_isLoadingUsers)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 44),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_monitoredUsers.isEmpty)
              _buildEmptyState()
            else
              _buildUsersList(),
          ],
        ),
      ),
    );
  }

  int get _activeMonitoredCount {
    var total = 0;
    for (final user in _monitoredUsers) {
      final uid = user['uid'] as String? ?? '';
      if (_isUserOnline(uid)) total++;
    }
    return total;
  }

  Widget _buildHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Selamat datang',
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                _familyName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.heading3.copyWith(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const FamilySettingsScreen(),
                ),
              );
            },
            borderRadius: BorderRadius.circular(14),
            child: Ink(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: const Icon(
                Icons.settings_rounded,
                color: AppColors.primaryDark,
                size: 22,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFamilyOverviewCard() {
    final activeCount = _activeMonitoredCount;
    final totalCount = _monitoredUsers.length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primaryDark.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.family_restroom_rounded,
                  color: AppColors.primaryDark,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pemantauan keluarga',
                      style: AppTextStyles.bodyLarge.copyWith(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Pantau lokasi dan kondisi pengguna secara real-time.',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.textSecondary,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _FamilyStatusPill(
                  icon: Icons.people_alt_rounded,
                  label: 'Dipantau',
                  value: '$totalCount pengguna',
                  color: AppColors.primaryDark,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _FamilyStatusPill(
                  icon: Icons.circle_rounded,
                  label: 'Status',
                  value: activeCount > 0 ? '$activeCount aktif' : 'Tidak aktif',
                  color: activeCount > 0
                      ? AppColors.success
                      : AppColors.warning,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAddUserAction() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _isSubmittingPairingRequest ? null : _onAddUserPressed,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            color: AppColors.primaryDark,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryDark.withValues(alpha: 0.16),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  _isSubmittingPairingRequest
                      ? Icons.sync_rounded
                      : Icons.person_add_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  _isSubmittingPairingRequest
                      ? 'Mengirim Permintaan...'
                      : 'Tambah Pengguna',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.button.copyWith(
                    fontSize: 18,
                    letterSpacing: 0,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                Icons.chevron_right_rounded,
                color: Colors.white.withValues(alpha: 0.86),
                size: 26,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActiveSosBanner() {
    final userName = _readString(_activeSosData?['userName']) ?? 'Pengguna';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFEF4444),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFEF4444).withValues(alpha: 0.16),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(Icons.warning_rounded, color: Colors.white, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'SOS Aktif - $userName membutuhkan bantuan',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyLarge.copyWith(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _buildSosActionButton(
                  icon: Icons.location_on_rounded,
                  label: 'Lihat Lokasi',
                  onTap: _openSosLocation,
                  isFilled: true,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildSosActionButton(
                  icon: Icons.check_circle_rounded,
                  label: 'Tandai Ditangani',
                  onTap: resolveSosAlert,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSosActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isFilled = false,
  }) {
    final foregroundColor = isFilled ? const Color(0xFFEF4444) : Colors.white;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: isFilled ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: isFilled
                ? null
                : Border.all(color: Colors.white, width: 1.2),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: foregroundColor),
              const SizedBox(width: 6),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: foregroundColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.045),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.primaryDark.withValues(alpha: 0.09),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.people_outline_rounded,
              size: 36,
              color: AppColors.primaryDark,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Belum ada pengguna terhubung',
            style: AppTextStyles.bodyLarge.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'Tekan Tambah Pengguna dan masukkan kode pairing dari akun tunanetra.',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textSecondary,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.primaryDark.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  color: AppColors.primaryDark,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Kartu monitoring akan muncul otomatis setelah pengguna terhubung.',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.primaryDark,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUsersList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...List.generate(_monitoredUsers.length, (index) {
          final user = _monitoredUsers[index];
          final uid = user['uid'] as String? ?? '';
          final location = _latestLocations[uid];
          final isOnline = _isUserOnline(uid);
          final phoneBatteryLevel = _getLiveBatteryLevel(uid);
          final smartCaneBatteryLevel = _getLiveSmartCaneBatteryLevel(uid);

          return GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (ctx) => FamilyHistoryScreen(
                    targetUid: user['uid'],
                    familyId: _resolvedFamilyId,
                  ),
                ),
              );
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.textPrimary.withValues(alpha: 0.045),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                    child: _buildUserCardHeader(
                      user: user,
                      isOnline: isOnline,
                      lastActiveAt: location?.timestamp,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    child: _buildBatteryStatusIndicators(
                      smartCaneBatteryLevel: smartCaneBatteryLevel,
                      phoneBatteryLevel: phoneBatteryLevel,
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                    child: Row(
                      children: [
                        _buildManagePlacesButton(user),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildUserCardActionButton(
                            icon: Icons.map_rounded,
                            label: 'Lihat Lokasi',
                            isPrimary: true,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (ctx) => FamilyHistoryScreen(
                                    targetUid: user['uid'],
                                    familyId: _resolvedFamilyId,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildUserCardActionButton(
                            icon: Icons.history_rounded,
                            label: 'Riwayat',
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (ctx) => FamilyHistoryDetailScreen(
                                    targetUid: user['uid'],
                                    familyId: _resolvedFamilyId,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildUserCardActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isPrimary = false,
  }) {
    final backgroundColor = isPrimary
        ? AppColors.primaryDark
        : AppColors.primaryLight.withValues(alpha: 0.14);
    final foregroundColor = isPrimary ? Colors.white : AppColors.primaryDark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(12),
            border: isPrimary
                ? null
                : Border.all(
                    color: AppColors.primaryDark.withValues(alpha: 0.12),
                  ),
            boxShadow: isPrimary
                ? [
                    BoxShadow(
                      color: AppColors.primaryDark.withValues(alpha: 0.12),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: foregroundColor, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    maxLines: 1,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: foregroundColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildManagePlacesButton(Map<String, dynamic> user) {
    return Tooltip(
      message: 'Kelola tempat',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => FamilyManagePlacesScreen(
                  ownerUid: user['uid'] as String?,
                  ownerName: user['name'] as String?,
                ),
              ),
            );
          },
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primaryLight.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.primaryDark.withValues(alpha: 0.12),
              ),
            ),
            child: const Icon(
              Icons.add_location_alt_rounded,
              color: AppColors.primaryDark,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUserCardHeader({
    required Map<String, dynamic> user,
    required bool isOnline,
    required DateTime? lastActiveAt,
  }) {
    final userName = (user['name'] as String?)?.trim();
    final displayName = userName?.isNotEmpty == true ? userName! : 'Pengguna';
    final avatarText = displayName.characters.first.toUpperCase();

    final avatar = Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: AppColors.primaryDark,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          avatarText,
          style: AppTextStyles.heading2.copyWith(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );

    final userInfo = Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            displayName,
            style: AppTextStyles.bodyLarge.copyWith(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: AppColors.textPrimary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: isOnline ? AppColors.success : AppColors.warning,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  isOnline
                      ? 'Aktif'
                      : lastActiveAt != null
                      ? 'Aktif ${_formatTimeAgo(lastActiveAt)}'
                      : 'Tidak aktif',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: isOnline ? AppColors.success : AppColors.warning,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    return Row(children: [avatar, const SizedBox(width: 12), userInfo]);
  }

  Widget _buildBatteryStatusIndicators({
    required double? smartCaneBatteryLevel,
    required double? phoneBatteryLevel,
  }) {
    return Row(
      children: [
        Expanded(
          child: _buildBatteryBadge(
            label: 'SmartCane',
            semanticLabel: 'Baterai tongkat pintar',
            battery: smartCaneBatteryLevel,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildBatteryBadge(
            label: 'HP',
            semanticLabel: 'Baterai HP pengguna',
            battery: phoneBatteryLevel,
          ),
        ),
      ],
    );
  }

  Widget _buildBatteryBadge({
    required String label,
    required String semanticLabel,
    required double? battery,
  }) {
    final batteryLevel = battery;
    final hasBattery = batteryLevel != null;
    final batteryColor = hasBattery
        ? _getBatteryColor(batteryLevel)
        : AppColors.textSecondary;
    final percentText = hasBattery
        ? '${batteryLevel.toInt()}%'
        : 'Belum terbaca';
    final fillWidth = hasBattery ? math.max(0.08, batteryLevel / 100.0) : 0.0;

    return Semantics(
      label: '$semanticLabel: $percentText',
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  percentText,
                  maxLines: 1,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: hasBattery ? AppColors.textPrimary : batteryColor,
                    fontSize: hasBattery ? 15 : 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: Container(
                height: 4,
                color: const Color(0xFFE2E8F0),
                child: hasBattery
                    ? Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: fillWidth,
                          heightFactor: 1,
                          child: Container(color: batteryColor),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  double? _parseBatteryLevel(dynamic value) {
    if (value is num) {
      return value.toDouble().clamp(0.0, 100.0);
    }
    if (value is String) {
      final parsed = double.tryParse(value);
      return parsed?.clamp(0.0, 100.0);
    }
    return null;
  }

  Timestamp? _parseTimestamp(dynamic value) {
    if (value is Timestamp) return value;
    if (value is num) {
      return Timestamp.fromMillisecondsSinceEpoch(value.round());
    }
    return null;
  }

  String? _readString(dynamic value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  bool _isLiveTrackingFresh(Timestamp? updatedAt) {
    if (updatedAt == null) return false;
    return _liveTrackingNow.difference(updatedAt.toDate()).inSeconds <= 60;
  }

  String _formatTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inSeconds < 60) {
      return 'baru saja';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes} menit yang lalu';
    } else if (difference.inHours < 24) {
      return '${difference.inHours} jam yang lalu';
    } else {
      return '${difference.inDays} hari yang lalu';
    }
  }
}

class _FamilyStatusPill extends StatelessWidget {
  const _FamilyStatusPill({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 70),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption.copyWith(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                style: AppTextStyles.caption.copyWith(
                  fontSize: 13,
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
