# Dokumentasi: Koneksi Family & TunaNetra Users

## 📊 Struktur Data di Firestore

### Collection: `users`

#### 1. **Family User** (Pengawas)
```json
{
  "uid": "family_user_123",
  "email": "family@example.com",
  "name": "Ibu Ani",
  "phoneNumber": "08123456789",
  "userType": "family",
  "createdAt": "2026-04-29T10:00:00Z",
  "isEmailVerified": true,
  
  // ✅ OPSI 1: Single TunaNetra User
  "pairedUserUid": "tunanetra_user_456",
  
  // ✅ OPSI 2: Multiple TunaNetra Users
  "pairedUserUids": [
    "tunanetra_user_456",
    "tunanetra_user_789"
  ]
}
```

#### 2. **TunaNetra User** (Yang dimonitor)
```json
{
  "uid": "tunanetra_user_456",
  "email": "tunanetra@example.com",
  "name": "Adi (Tuna Netra)",
  "phoneNumber": "08987654321",
  "userType": "tunanetra",
  "pairingCode": "USER12345",  // Untuk pairing awal
  "createdAt": "2026-04-29T09:00:00Z",
  "isEmailVerified": true,
  "familyContacts": [
    {
      "name": "Ibu Ani",
      "phoneNumber": "08123456789",
      "email": "family@example.com"
    }
  ]
}
```

---

## 🔄 Alur Kerja

### 1. **Login Family User**
```
Login → Get Family User Document → Extract pairedUserUid(s)
```

### 2. **Load Monitored Users** (di Family Home Screen)
```
getFamilyId()
    ↓
getTunaNetraUsersByFamilyId(familyId)
    ├─ Fetch family document
    ├─ Extract pairedUserUid(s)
    ├─ Loop setiap UID
    └─ Fetch TunaNetra user documents
    ↓
Display List of TunaNetra Users
```

---

## 💻 Kode Implementation

### Method di UserService

```dart
Future<List<Map<String, dynamic>>> getTunaNetraUsersByFamilyId(
  String familyId,
) async {
  // Step 1: Fetch family user
  final familyDoc = await _firestore
      .collection('users')
      .doc(familyId)
      .get();

  // Step 2: Get paired UIDs (support both single & array)
  final pairedUserUids = <String>[];
  
  // Support single pairedUserUid
  if (familyData['pairedUserUid'] is String) {
    pairedUserUids.add(familyData['pairedUserUid']);
  }
  
  // Support array pairedUserUids
  if (familyData['pairedUserUids'] is List) {
    pairedUserUids.addAll(
      List<String>.from(familyData['pairedUserUids'])
    );
  }

  // Step 3: Fetch each TunaNetra user
  final users = <Map<String, dynamic>>[];
  for (final uid in pairedUserUids) {
    final userDoc = await _firestore
        .collection('users')
        .doc(uid)
        .get();
    
    if (userDoc.exists && userDoc['userType'] == 'tunanetra') {
      users.add(userDoc.data());
    }
  }
  
  return users;
}
```

### Usage di FamilyHomeScreen

```dart
@override
void initState() {
  super.initState();
  _loadMonitoredUsers();
}

Future<void> _loadMonitoredUsers() async {
  final userService = UserService();
  final users = await userService.getTunaNetraUsersByFamilyId(
    widget.familyId,
  );
  
  setState(() {
    _monitoredUsers = users;
  });
}
```

### Display dengan FutureBuilder

```dart
FutureBuilder<List<Map<String, dynamic>>>(
  future: UserService().getTunaNetraUsersByFamilyId(familyId),
  builder: (context, snapshot) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return CircularProgressIndicator();
    }
    
    if (snapshot.hasError) {
      return Text('Error: ${snapshot.error}');
    }
    
    final users = snapshot.data ?? [];
    
    if (users.isEmpty) {
      return Text('Belum ada pengguna terhubung');
    }
    
    return ListView.builder(
      itemCount: users.length,
      itemBuilder: (context, index) {
        final user = users[index];
        return ListTile(
          title: Text(user['name']),
          subtitle: Text(user['email']),
        );
      },
    );
  },
)
```

---

## ✅ Checklist Setup Firestore

- [ ] Collection `users` sudah dibuat di Firestore
- [ ] Family user dokumen memiliki field:
  - [ ] `uid` (document ID)
  - [ ] `userType: "family"`
  - [ ] `pairedUserUid` ATAU `pairedUserUids`
- [ ] TunaNetra user dokumen memiliki field:
  - [ ] `uid` (document ID)
  - [ ] `userType: "tunanetra"`
  - [ ] `name`, `email`, `phoneNumber`
- [ ] Security Rules memungkinkan read dari family ke semua users

---

## 🚨 Troubleshooting

### Problem 1: "Tidak ada TunaNetra user yang terhubung"
**Debug:**
1. Buka Firestore → collection `users`
2. Cari family user document
3. Verifikasi field `pairedUserUid` atau `pairedUserUids` ada dan tidak kosong
4. Cek console log di `flutter logs` untuk detail

### Problem 2: "Invalid argument(s): A document path must be a non-empty string"
**Penyebab:** `pairedUserUid` kosong atau null
**Solusi:** 
- Update family user dengan `pairedUserUid` yang valid
- Atau gunakan `pairedUserUids: []` jika belum ada user

### Problem 3: TunaNetra user ditemukan tapi tidak ditampilkan
**Debug:**
1. Verifikasi field `userType: "tunanetra"` pada user document
2. Check console log untuk melihat apa yang diterima

---

## 📝 Contoh Setup Manual di Firestore

### Setup Contoh:

**Document:** `users/family_user_123`
```json
{
  "uid": "family_user_123",
  "email": "family@example.com",
  "name": "Ibu Ani",
  "phoneNumber": "08123456789",
  "userType": "family",
  "pairedUserUids": ["tunanetra_user_456"],
  "createdAt": "2026-04-29"
}
```

**Document:** `users/tunanetra_user_456`
```json
{
  "uid": "tunanetra_user_456",
  "email": "adi@example.com",
  "name": "Adi Pratama",
  "phoneNumber": "08987654321",
  "userType": "tunanetra",
  "pairingCode": "USER12345",
  "createdAt": "2026-04-29"
}
```

Setelah setup ini, ketika family user login dan buka home screen, akan menampilkan "Adi Pratama" di list monitoring.
