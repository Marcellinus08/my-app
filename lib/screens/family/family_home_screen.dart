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
  Map<String, StreamSubscription<FamilyLocation>?> _subscriptions = {};
  Map<String, StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?>
  _userProfileSubscriptions = {};
  Map<String, Map<String, dynamic>?> _liveTrackingData = {};
  Map<String, StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?>
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

  // Debug info
  String? _debugPairingCode;
  String? _debugErrorMessage;
  Timer? _liveTrackingFreshnessTimer;
  DateTime _liveTrackingNow = DateTime.now();
  late AnimationController _rotationController;
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

    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 25),
    )..repeat();

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeOut));

    _fadeController.forward();
  }

  Future<void> _loadMonitoredUsers() async {
    try {
      print(
        '\nΓòöΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòù',
      );
      print('Γòæ [FAMILY HOME] Loading Monitored Users (by Family ID)  Γòæ');
      print(
        'ΓòÜΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓò¥',
      );

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

        for (final uid in _subscriptions.keys.toList()) {
          if (!activeUids.contains(uid)) {
            _subscriptions.remove(uid)?.cancel();
            _latestLocations.remove(uid);
          }
        }

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

          // Set debug info
          _debugPairingCode = 'Method: pairedUserUid';
          _debugErrorMessage = users.isEmpty
              ? 'Tidak ada TunaNetra user yang terhubung'
              : null;
        });
      }

      // Start listening to each user's location
      for (var user in users) {
        final uid = user['uid'] as String?;
        if (uid != null && uid.isNotEmpty) {
          _subscribeToUserLocation(uid);
          _subscribeToUserProfile(uid);
          _subscribeToLiveTracking(uid);
        }
      }

      print('Γ£à Monitoring users loaded: ${users.length}');
    } catch (e) {
      print('Γ¥î Error loading monitored users: $e');
      if (mounted) {
        setState(() {
          _isLoadingUsers = false;
          _debugErrorMessage = 'Error: ${e.toString()}';
        });
      }
    }
  }

  void _subscribeToUserLocation(String uid) {
    if (_subscriptions[uid] != null) {
      _subscriptions[uid]?.cancel();
    }

    final stream = _locationService.listenToRealtime(uid, storeHistory: true);
    final sub = stream.listen((location) {
      if (mounted) {
        setState(() {
          _latestLocations[uid] = location;
        });
      }
    });

    _subscriptions[uid] = sub;
  }

  void _subscribeToLiveTracking(String uid) {
    if (_liveTrackingSubscriptions[uid] != null) {
      _liveTrackingSubscriptions[uid]?.cancel();
    }

    final sub = _firestore
        .collection('live_tracking')
        .doc(uid)
        .snapshots()
        .listen((snapshot) {
          if (mounted) {
            setState(() {
              _liveTrackingData[uid] = snapshot.data();
            });
          }
        });

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
    final familyId = widget.familyId.trim().isNotEmpty
        ? widget.familyId.trim()
        : (AuthService().currentUserId ?? '');

    if (familyId.isEmpty) {
      debugPrint('[FamilyHome] Skip SOS listener, familyId empty');
      return;
    }

    _resolvedFamilyId = familyId;
    _activeSosSubscription?.cancel();
    _activeSosSubscription = _firestore
        .collection('sos_alerts')
        .where('familyUids', arrayContains: familyId)
        .where('status', isEqualTo: 'active')
        .orderBy('createdAt', descending: true)
        .limit(1)
        .snapshots()
        .listen(
          (snapshot) {
            if (!mounted) return;
            DocumentSnapshot<Map<String, dynamic>>? activeDoc;
            Map<String, dynamic>? activeData;

            if (snapshot.docs.isNotEmpty) {
              activeDoc = snapshot.docs.first;
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

  void _notifyActiveSos(String sosId, Map<String, dynamic> data) {
    if (_lastNotifiedSosId == sosId) return;
    _lastNotifiedSosId = sosId;

    NotificationService.instance.showSosFullScreenNotification(data);

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
    final lat = _parseDouble(liveData['lat']);
    final lng = _parseDouble(liveData['lng']);
    final updatedAt = _parseTimestamp(liveData['updatedAt']);

    return connectionStatus == 'online' &&
        lat != null &&
        lng != null &&
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
    final controller = TextEditingController();

    final pairingCode = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            'Tambah Pengguna',
            style: AppTextStyles.heading3.copyWith(fontWeight: FontWeight.w800),
          ),
          content: TextField(
            controller: controller,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: 'Kode Pairing',
              hintText: 'Masukkan kode dari TunaNetra',
              prefixIcon: const Icon(Icons.vpn_key_rounded),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onSubmitted: (_) {
              Navigator.pop(dialogContext, controller.text.trim());
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Batal'),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(dialogContext, controller.text.trim());
              },
              icon: const Icon(Icons.send_rounded, size: 18),
              label: const Text('Kirim'),
            ),
          ],
        );
      },
    );

    controller.dispose();

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

  void _openSosLocation() {
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

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) =>
            FamilyHistoryScreen(targetUid: userId, familyId: _resolvedFamilyId),
      ),
    );
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
    final familyId = _resolvedFamilyId.isNotEmpty
        ? _resolvedFamilyId
        : (AuthService().currentUserId ?? '');
    if (familyId.isEmpty) {
      throw Exception('Family UID kosong');
    }

    final userId = _readString(_activeSosData?['userId']);
    var query = _firestore
        .collection('sos_alerts')
        .where('familyUids', arrayContains: familyId)
        .where('status', isEqualTo: 'active');

    if (userId != null) {
      query = query.where('userId', isEqualTo: userId);
    }

    final snapshot = await query
        .orderBy('createdAt', descending: true)
        .limit(1)
        .get();
    if (snapshot.docs.isEmpty) {
      throw Exception('SOS aktif tidak ditemukan');
    }

    await snapshot.docs.first.reference.update({
      'status': 'resolved',
      'resolvedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  void dispose() {
    for (var sub in _subscriptions.values) {
      sub?.cancel();
    }
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
    _rotationController.dispose();
    _fadeController.dispose();
    _locationService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFFFAFBFC),
              AppColors.primaryLight.withOpacity(0.08),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Stack(
          children: [
            // Animated rotating circles background
            ...List.generate(4, (index) {
              return AnimatedBuilder(
                animation: _rotationController,
                builder: (context, child) {
                  final angle =
                      _rotationController.value * 2 * math.pi +
                      (index * math.pi / 2);
                  final size = 120.0 + (index * 40);
                  final distance = 150.0 + (index * 30);

                  return Positioned(
                    left:
                        MediaQuery.of(context).size.width / 2 +
                        math.cos(angle) * distance -
                        size / 2,
                    top:
                        MediaQuery.of(context).size.height / 3 +
                        math.sin(angle) * distance -
                        size / 2,
                    child: Container(
                      width: size,
                      height: size,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            AppColors.primaryLight.withOpacity(0.06),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            }),

            // Main content with fade animation
            FadeTransition(opacity: _fadeAnimation, child: _buildMainContent()),
          ],
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    return SafeArea(
      child: Column(
        children: [
          // Clean & Elegant Header
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [const Color(0xFF0D47A1), const Color(0xFF1565C0)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0D47A1).withOpacity(0.2),
                  blurRadius: 25,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left: Greeting + Family Name
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Selamat Datang',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: Colors.white.withOpacity(0.85),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        width: double.infinity,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            _familyName,
                            maxLines: 1,
                            style: AppTextStyles.heading1.copyWith(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Monitoring ${_monitoredUsers.length} pengguna',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const FamilySettingsScreen(),
                      ),
                    );
                  },
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withOpacity(0.25),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.settings_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (_activeSosData != null) _buildActiveSosBanner(),

          // Monitored Users List
          Expanded(
            child: _isLoadingUsers
                ? Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppColors.primary,
                      ),
                    ),
                  )
                : _monitoredUsers.isEmpty
                ? _buildEmptyState()
                : _buildUsersList(),
          ),

          // Add User Button at Bottom
          Container(
            padding: const EdgeInsets.all(20),
            child: GestureDetector(
              onTap: _isSubmittingPairingRequest ? null : _onAddUserPressed,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.3),
                      blurRadius: 15,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.person_add_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _isSubmittingPairingRequest
                          ? 'Mengirim Permintaan...'
                          : 'Tambah Pengguna',
                      style: AppTextStyles.bodyLarge.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveSosBanner() {
    final userName = _readString(_activeSosData?['userName']) ?? 'Pengguna';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.error,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.error.withOpacity(0.25),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_rounded, color: Colors.white, size: 24),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'SOS Aktif - $userName membutuhkan bantuan',
                  style: AppTextStyles.bodyLarge.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _openSosLocation,
                  icon: const Icon(Icons.location_on_rounded, size: 18),
                  label: const Text('Lihat Lokasi'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.error,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: resolveSosAlert,
                  icon: const Icon(Icons.check_circle_rounded, size: 18),
                  label: const Text('Tandai Ditangani'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white, width: 1.5),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: AppColors.primary.withOpacity(0.08),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0F172A).withOpacity(0.06),
                  blurRadius: 28,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.08),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.people_outline_rounded,
                    size: 44,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Belum ada pengguna terhubung',
                  style: AppTextStyles.heading3.copyWith(
                    color: AppColors.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  'Setelah akun keluarga terhubung, kartu monitoring akan tampil otomatis di sini.',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.45,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceLight,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: AppColors.primary.withOpacity(0.06),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.add_circle_outline_rounded,
                          color: AppColors.primary,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Siapkan koneksi baru',
                              style: AppTextStyles.bodyLarge.copyWith(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Tekan tombol Tambah Pengguna untuk menghubungkan akun TunaNetra ke keluarga.',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.textSecondary,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUsersList() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        children: List.generate(_monitoredUsers.length, (index) {
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
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.white, Colors.white.withOpacity(0.95)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.12),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
                border: Border.all(
                  color: AppColors.primary.withOpacity(0.1),
                  width: 1.5,
                ),
              ),
              child: Column(
                children: [
                  // Header Section with Battery
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.primary.withOpacity(0.06),
                          AppColors.primary.withOpacity(0.02),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(24),
                        topRight: Radius.circular(24),
                      ),
                      border: Border(
                        bottom: BorderSide(
                          color: AppColors.primary.withOpacity(0.08),
                          width: 1,
                        ),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // User Avatar
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                AppColors.primary,
                                AppColors.primary.withOpacity(0.7),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withOpacity(0.2),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              (user['name'] as String).characters.first
                                  .toUpperCase(),
                              style: AppTextStyles.heading2.copyWith(
                                color: Colors.white,
                                fontSize: 24,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),

                        // User name and status
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                user['name'] ?? 'Pengguna',
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
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color: isOnline
                                          ? Colors.green
                                          : Colors.orange,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: isOnline
                                              ? Colors.green
                                              : Colors.orange,
                                          blurRadius: 6,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    isOnline ? 'Aktif' : 'Tidak aktif',
                                    style: AppTextStyles.bodySmall.copyWith(
                                      color: isOnline
                                          ? Colors.green
                                          : Colors.orange,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),

                        // Battery Indicator
                        _buildBatteryStatusIndicators(
                          smartCaneBatteryLevel: smartCaneBatteryLevel,
                          phoneBatteryLevel: phoneBatteryLevel,
                        ),
                      ],
                    ),
                  ),

                  // Contact Information
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    child: Column(
                      children: [
                        // Phone Number
                        if (user['phoneNumber'] != null &&
                            (user['phoneNumber'] as String).isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    Icons.phone_rounded,
                                    size: 18,
                                    color: Colors.blue,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Nomor Telepon',
                                        style: AppTextStyles.bodySmall.copyWith(
                                          color: AppColors.textSecondary,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        user['phoneNumber'] ?? '-',
                                        style: AppTextStyles.bodyMedium
                                            .copyWith(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 13,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),

                        // Email
                        if (user['email'] != null &&
                            (user['email'] as String).isNotEmpty)
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  Icons.email_rounded,
                                  size: 18,
                                  color: Colors.green,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Email',
                                      style: AppTextStyles.bodySmall.copyWith(
                                        color: AppColors.textSecondary,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      user['email'] ?? '-',
                                      style: AppTextStyles.bodyMedium.copyWith(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),

                  // Device Status Section
                  if (location != null) ...[
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.primary.withOpacity(0.1),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildDeviceStatusInfo(
                            icon: Icons.gps_fixed_rounded,
                            label: 'GPS',
                            value: location.gpsEnabled ? 'Aktif' : 'Mati',
                            isActive: location.gpsEnabled,
                          ),
                          Container(
                            width: 1,
                            height: 28,
                            color: AppColors.primary.withOpacity(0.1),
                          ),
                          _buildDeviceStatusInfo(
                            icon: Icons.wifi_rounded,
                            label: 'Internet',
                            value: location.internetAvailable ? 'OK' : 'Lemah',
                            isActive: location.internetAvailable,
                          ),
                          Container(
                            width: 1,
                            height: 28,
                            color: AppColors.primary.withOpacity(0.1),
                          ),
                          _buildDeviceStatusInfo(
                            icon: Icons.directions_walk_rounded,
                            label: 'Status',
                            value: location.navigationStatus == 'navigating'
                                ? 'Navigasi'
                                : location.speed > 0.8
                                ? 'Berjalan'
                                : 'Diam',
                            isActive: location.navigationStatus == 'navigating',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Last Activity Time
                  if (location != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Icon(
                            Icons.schedule_rounded,
                            size: 16,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Lokasi terakhir: ${_formatTimeAgo(location.timestamp)}',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Action Button
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        _buildManagePlacesButton(user),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
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
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  gradient: AppColors.primaryGradient,
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.primary.withOpacity(0.2),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.map_rounded,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Lihat Detail Lokasi',
                                      style: AppTextStyles.bodyMedium.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
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
                ],
              ),
            ),
          );
        }),
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
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.18),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              Icons.add_location_alt_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBatteryIndicator(double battery) {
    final fillHeight = 50.0 * math.max(0.08, battery / 100.0);
    final batteryColor = _getBatteryColor(battery);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 38,
          height: 56,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 32,
                height: 54,
                decoration: BoxDecoration(
                  color: batteryColor.withOpacity(0.06),
                  border: Border.all(
                    color: batteryColor.withOpacity(0.5),
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(9),
                ),
              ),
              Positioned(
                top: 6,
                child: Container(
                  width: 11,
                  height: 3,
                  decoration: BoxDecoration(
                    color: batteryColor.withOpacity(0.55),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              Positioned(
                bottom: 3,
                child: Container(
                  width: 26,
                  height: 50,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(7),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      width: double.infinity,
                      height: fillHeight,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [batteryColor, batteryColor.withOpacity(0.6)],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              _buildBatteryPercentText(
                '${battery.toInt()}%',
                color: AppColors.textPrimary,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildUnknownBatteryIndicator() {
    return SizedBox(
      width: 38,
      height: 56,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 32,
            height: 54,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.08),
              border: Border.all(
                color: AppColors.primary.withOpacity(0.5),
                width: 2,
              ),
              borderRadius: BorderRadius.circular(9),
            ),
          ),
          Positioned(
            top: 6,
            child: Container(
              width: 11,
              height: 3,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.55),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          Center(
            child: Text(
              '?',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.primary,
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBatteryStatusIndicators({
    required double? smartCaneBatteryLevel,
    required double? phoneBatteryLevel,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (smartCaneBatteryLevel != null)
          _buildBatteryPercentageIndicator(smartCaneBatteryLevel)
        else
          _buildUnknownBatteryPercentageIndicator(),
        const SizedBox(width: 8),
        if (phoneBatteryLevel != null)
          _buildBatteryIndicator(phoneBatteryLevel)
        else
          _buildUnknownBatteryIndicator(),
      ],
    );
  }

  Widget _buildBatteryPercentageIndicator(double battery) {
    final fillHeight = 52.0 * math.max(0.08, battery / 100.0);
    final batteryColor = _getBatteryColor(battery);

    return SizedBox(
      width: 38,
      height: 56,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ClipPath(
            clipper: _BatteryPercentShapeClipper(),
            child: Container(
              width: 32,
              height: 54,
              color: batteryColor.withOpacity(0.08),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  width: double.infinity,
                  height: fillHeight,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [batteryColor, batteryColor.withOpacity(0.58)],
                    ),
                  ),
                ),
              ),
            ),
          ),
          CustomPaint(
            size: const Size(32, 54),
            painter: _BatteryPercentOutlinePainter(
              color: batteryColor.withOpacity(0.5),
            ),
          ),
          _buildBatteryPercentText(
            '${battery.toInt()}%',
            color: AppColors.textPrimary,
          ),
        ],
      ),
    );
  }

  Widget _buildUnknownBatteryPercentageIndicator() {
    return SizedBox(
      width: 38,
      height: 56,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ClipPath(
            clipper: _BatteryPercentShapeClipper(),
            child: Container(
              width: 32,
              height: 54,
              color: AppColors.primary.withOpacity(0.08),
            ),
          ),
          CustomPaint(
            size: const Size(32, 54),
            painter: _BatteryPercentOutlinePainter(
              color: AppColors.primary.withOpacity(0.5),
            ),
          ),
          Text(
            '?',
            style: AppTextStyles.heading2.copyWith(
              color: AppColors.primary,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBatteryPercentText(String text, {required Color color}) {
    return Center(
      child: SizedBox(
        width: 22,
        height: 12,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySmall.copyWith(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
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

  double? _parseDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value);
    }
    return null;
  }

  Timestamp? _parseTimestamp(dynamic value) {
    return value is Timestamp ? value : null;
  }

  String? _readString(dynamic value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  bool _isLiveTrackingFresh(Timestamp? updatedAt) {
    if (updatedAt == null) return false;
    return _liveTrackingNow.difference(updatedAt.toDate()).inSeconds <= 30;
  }

  Widget _buildDeviceStatusInfo({
    required IconData icon,
    required String label,
    required String value,
    required bool isActive,
  }) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: isActive
                  ? AppColors.primary.withOpacity(0.1)
                  : Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 16,
              color: isActive ? AppColors.primary : Colors.orange,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textSecondary,
              fontSize: 9,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: AppTextStyles.bodySmall.copyWith(
              color: isActive ? AppColors.primary : Colors.orange,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
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

class _BatteryPercentShapeClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) => _batteryPercentShapePath(size);

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _BatteryPercentOutlinePainter extends CustomPainter {
  final Color color;

  const _BatteryPercentOutlinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(_batteryPercentShapePath(size), paint);
  }

  @override
  bool shouldRepaint(covariant _BatteryPercentOutlinePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

Path _batteryPercentShapePath(Size size) {
  final w = size.width;
  final h = size.height;

  return Path()
    ..moveTo(w * 0.50, h * 0.02)
    ..cubicTo(w * 0.70, h * 0.02, w * 0.76, h * 0.11, w * 0.76, h * 0.20)
    ..lineTo(w * 0.76, h * 0.29)
    ..cubicTo(w * 0.76, h * 0.37, w * 0.88, h * 0.38, w * 0.94, h * 0.45)
    ..cubicTo(w * 0.98, h * 0.52, w * 0.97, h * 0.63, w * 0.97, h * 0.72)
    ..lineTo(w * 0.97, h * 0.83)
    ..cubicTo(w * 0.97, h * 0.90, w * 0.82, h * 0.91, w * 0.82, h * 0.96)
    ..cubicTo(w * 0.82, h * 1.00, w * 0.70, h * 1.00, w * 0.50, h * 1.00)
    ..cubicTo(w * 0.30, h * 1.00, w * 0.18, h * 1.00, w * 0.18, h * 0.96)
    ..cubicTo(w * 0.18, h * 0.91, w * 0.03, h * 0.90, w * 0.03, h * 0.83)
    ..lineTo(w * 0.03, h * 0.72)
    ..cubicTo(w * 0.03, h * 0.63, w * 0.02, h * 0.52, w * 0.06, h * 0.45)
    ..cubicTo(w * 0.12, h * 0.38, w * 0.24, h * 0.37, w * 0.24, h * 0.29)
    ..lineTo(w * 0.24, h * 0.20)
    ..cubicTo(w * 0.24, h * 0.11, w * 0.30, h * 0.02, w * 0.50, h * 0.02)
    ..close();
}
