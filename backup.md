#!/usr/bin/env python3

import json
import os
import statistics
import threading
import time
from collections import deque
import collections
import numpy as np

import board
import dbus
import dbus.mainloop.glib
import dbus.service
import RPi.GPIO as GPIO
from adafruit_ina219 import INA219
from busio import I2C
from gi.repository import GLib


BLUEZ_SERVICE_NAME = "org.bluez"
DBUS_OM_IFACE = "org.freedesktop.DBus.ObjectManager"
DBUS_PROP_IFACE = "org.freedesktop.DBus.Properties"

GATT_MANAGER_IFACE = "org.bluez.GattManager1"
GATT_SERVICE_IFACE = "org.bluez.GattService1"
GATT_CHRC_IFACE = "org.bluez.GattCharacteristic1"

LE_ADVERTISING_MANAGER_IFACE = "org.bluez.LEAdvertisingManager1"
LE_ADVERTISEMENT_IFACE = "org.bluez.LEAdvertisement1"

AGENT_MANAGER_IFACE = "org.bluez.AgentManager1"
AGENT_IFACE = "org.bluez.Agent1"
DEVICE_IFACE = "org.bluez.Device1"

AGENT_PATH = "/temanarah/agent"
APP_PATH = "/temanarah/gatt"
ADV_PATH = "/temanarah/advertisement0"

DEVICE_ID = "TA-CANE-0001"
DEVICE_PIN = "482913"
DEVICE_NAME = "TemanArah-Cane"

SERVICE_UUID = "0000a001-0000-1000-8000-00805f9b34fb"
SENSOR_CHARACTERISTIC_UUID = "0000a002-0000-1000-8000-00805f9b34fb"
PAIRING_CHARACTERISTIC_UUID = "0000a003-0000-1000-8000-00805f9b34fb"
IMU_CHARACTERISTIC_UUID = "0000a004-0000-1000-8000-00805f9b34fb"

STATE_FILE = "temanarah_cane_state.json"
BLUETOOTH_FALLBACK_PIN = "0000"
NOTIFY_CHUNK_BYTES = 20

SOS_BUTTON = 5

TRIG_CENTER = 17
ECHO_CENTER = 27
TRIG_LEFT = 22
ECHO_LEFT = 23
TRIG_RIGHT = 24
ECHO_RIGHT = 25

BATAS_AMAN_CM = 150
CONF_THRESHOLD = 0.35

# ── Center zone voting (anti-flicker road/walkable) ──────────
CENTER_ZONE_BUFFER_SIZE = 5
CENTER_ZONE_MIN_VOTES   = 3

# ── Cooldown per kategori label (detik) ──────────────────────
NO_COOLDOWN = 0
COOLDOWN_BY_LABEL = {
    "road":       NO_COOLDOWN,
    "pothole":    NO_COOLDOWN,
    "obstacle":   NO_COOLDOWN,
    "stair":      NO_COOLDOWN,
    "person":     5,
    "truck":      5,
    "bus":        5,
    "car":        5,
    "motorcycle": 5,
    "bicycle":    5,
    "puddle":     8,
    "zebracross": 8,
    "walkable":   NO_COOLDOWN,
}

LABEL_PRIORITY = {
    "road":       0,
    "pothole":    1,
    "obstacle":   2,
    "stair":      3,
    "puddle":     4,
    "person":     5,
    "truck":      6,
    "bus":        7,
    "car":        8,
    "motorcycle": 9,
    "bicycle":   10,
    "zebracross":11,
    "walkable":  12,
}

# Label kendaraan/orang yang bisa digabung jadi satu kalimat
VEHICLE_LABELS = {"person", "truck", "bus", "car", "motorcycle", "bicycle"}

# Nama Indonesia untuk penggabungan kalimat
LABEL_NAMES = {
    "person":     "orang",
    "truck":      "truk",
    "bus":        "bus",
    "car":        "mobil",
    "motorcycle": "motor",
    "bicycle":    "sepeda",
    "pothole":    "lubang jalan",
    "obstacle":   "halangan",
    "stair":      "tangga",
    "puddle":     "genangan air",
    "zebracross": "zebra cross",
}

LABEL_MESSAGES = {
    "road": {
        "kiri":   "",
        "tengah": "Bahaya! Anda berada di jalur kendaraan. Segera kembali ke trotoar.",
        "kanan":  "",
    },
    "pothole": {
        "kiri":   "Hati-hati, ada lubang jalan di sebelah kiri.",
        "tengah": "Hati-hati, ada lubang jalan di depan.",
        "kanan":  "Hati-hati, ada lubang jalan di sebelah kanan.",
    },
    "obstacle": {
        "kiri":   "Ada halangan di sebelah kiri.",
        "tengah": "Ada halangan di depan.",
        "kanan":  "Ada halangan di sebelah kanan.",
    },
    "stair": {
        "kiri":   "Terdeteksi tangga di sebelah kiri, hati-hati.",
        "tengah": "Terdeteksi tangga di depan, hati-hati.",
        "kanan":  "Terdeteksi tangga di sebelah kanan, hati-hati.",
    },
    "puddle": {
        "kiri":   "Ada genangan air di sebelah kiri.",
        "tengah": "Ada genangan air di depan.",
        "kanan":  "Ada genangan air di sebelah kanan.",
    },
    "zebracross": {
        "kiri":   "Ada zebra cross di kiri.",
        "tengah": "Terdeteksi zebra cross, perhatikan kendaraan.",
        "kanan":  "Ada zebra cross di kanan.",
    },
    "walkable": {
        "kiri":   "Jalur pejalan kaki ada di sebelah kiri. Segera kembali ke jalur aman.",
        "tengah": "Anda kembali ke jalur pejalan kaki.",
        "kanan":  "Jalur pejalan kaki ada di sebelah kanan. Segera kembali ke jalur aman.",
    },
}


def start_fall_detection_listener(sensor_characteristic):
    import subprocess

    def send_ble_event(payload):
        GLib.idle_add(sensor_characteristic.notify_text, payload)

    def worker():
        print("Fall detection listener aktif (subprocess)")
        proc = subprocess.Popen(
            ["python3", "fall_worker.py"],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
        )
        for line in proc.stdout:
            line = line.strip()
            if not line:
                continue
            try:
                data = json.loads(line)
                if data.get("e") == "fall":
                    payload = json.dumps(data, separators=(",", ":"))
                    send_ble_event(payload)
                    print(f"FALL DETECTED! prob={data['prob']:.2f}")
                else:
                    print("[FALL_WORKER]", line)
            except json.JSONDecodeError:
                print("[FALL_WORKER]", line)

        print("Fall worker process ended")

    threading.Thread(target=worker, daemon=True).start()

_button_thread_started = False
_battery_thread_started = False
_detection_thread_started = False
_background_running = True
voltage_samples = deque(maxlen=15)   # FIX: deque thread-safe, ganti list


# ════════════════════════════════════════════════════════════
# BLUETOOTH / DBUS HELPERS
# ════════════════════════════════════════════════════════════

def get_managed_objects(bus):
    manager = dbus.Interface(
        bus.get_object(BLUEZ_SERVICE_NAME, "/"),
        DBUS_OM_IFACE,
    )
    return manager.GetManagedObjects()


def find_adapter(bus):
    objects = get_managed_objects(bus)
    for path, interfaces in objects.items():
        if GATT_MANAGER_IFACE in interfaces and LE_ADVERTISING_MANAGER_IFACE in interfaces:
            return path
    raise RuntimeError("Adapter Bluetooth dengan GATT/Advertising manager tidak ditemukan")


def load_state():
    if not os.path.exists(STATE_FILE):
        return {"authorizedPhones": []}
    try:
        with open(STATE_FILE, "r", encoding="utf-8") as file:
            return json.load(file)
    except Exception:
        return {"authorizedPhones": []}


def save_state(state):
    with open(STATE_FILE, "w", encoding="utf-8") as file:
        json.dump(state, file, indent=2)


def set_device_trusted(bus, device_path):
    try:
        props = dbus.Interface(
            bus.get_object(BLUEZ_SERVICE_NAME, device_path),
            DBUS_PROP_IFACE,
        )
        props.Set(DEVICE_IFACE, "Trusted", dbus.Boolean(True))
        print("Bluetooth device trusted:", device_path)
    except Exception as error:
        print("Gagal set trusted:", error)


# ════════════════════════════════════════════════════════════
# BATTERY
# ════════════════════════════════════════════════════════════

def battery_percentage(voltage):
    min_voltage = 3.0
    max_voltage = 4.2
    percentage = ((voltage - min_voltage) / (max_voltage - min_voltage)) * 100
    return max(0, min(100, percentage))


def smooth_voltage(new_voltage):
    # FIX: deque dengan maxlen=15, tidak perlu pop manual
    voltage_samples.append(new_voltage)
    return sum(voltage_samples) / len(voltage_samples)


def round_to_nearest_5(percent):
    rounded = round(percent / 5) * 5
    return int(max(0, min(100, rounded)))


# ════════════════════════════════════════════════════════════
# SENSOR ULTRASONIK
# ════════════════════════════════════════════════════════════

def read_distance_once(trig, echo):
    GPIO.output(trig, False)
    time.sleep(0.0002)
    GPIO.output(trig, True)
    time.sleep(0.00001)
    GPIO.output(trig, False)

    timeout = time.time() + 0.03

    # FIX: catat pulse_start SETELAH echo jadi HIGH, bukan di dalam loop
    while GPIO.input(echo) == 0:
        if time.time() > timeout:
            return None
    pulse_start = time.time()

    timeout = time.time() + 0.03
    while GPIO.input(echo) == 1:
        if time.time() > timeout:
            return None
    pulse_end = time.time()

    distance = (pulse_end - pulse_start) * 17150
    if distance < 2 or distance > 400:
        return None
    return distance


def read_stable_distance(trig, echo, samples=3):
    values = []
    for _ in range(samples):
        value = read_distance_once(trig, echo)
        if value is not None:
            values.append(value)
        time.sleep(0.035)
    if not values:
        return None
    return round(statistics.median(values), 1)


def safe_distance(value):
    if value is None:
        return 400.0
    return float(value)


def decide_direction(left, center, right):
    left   = safe_distance(left)
    center = safe_distance(center)
    right  = safe_distance(right)

    if center > BATAS_AMAN_CM:
        return "MAJU"
    if left > right and left > BATAS_AMAN_CM:
        return "KIRI"
    if right > left and right > BATAS_AMAN_CM:
        return "KANAN"
    return "STOP"


def status_from_distance(center):
    center = safe_distance(center)
    if center < 50:
        return "danger"
    if center < BATAS_AMAN_CM:
        return "warning"
    return "safe"


def compact_direction(decision):
    return {"MAJU": "maju", "KIRI": "kiri", "KANAN": "kanan"}.get(decision, "stop")


# ════════════════════════════════════════════════════════════
# DETEKSI ML — TRACKER
# ════════════════════════════════════════════════════════════

class CenterZoneTracker:
    def __init__(self):
        self.buffer             = deque(maxlen=CENTER_ZONE_BUFFER_SIZE)
        self.last_stable        = None
        self.walkable_announced = False

    def update(self, center_label):
        self.buffer.append(center_label)

        votes = {}
        for item in self.buffer:
            if item is not None:
                votes[item] = votes.get(item, 0) + 1

        if not votes:
            return None

        winner       = max(votes, key=votes.get)
        winner_count = votes[winner]

        if winner_count < CENTER_ZONE_MIN_VOTES:
            return None

        if winner == self.last_stable:
            if winner == "road":
                if len(self.buffer) == CENTER_ZONE_BUFFER_SIZE and all(x == "road" for x in self.buffer):
                    return LABEL_MESSAGES["road"]["tengah"]
            return None

        self.last_stable = winner

        if winner == "road":
            self.walkable_announced = False
            return LABEL_MESSAGES["road"]["tengah"]

        if winner == "walkable":
            if not self.walkable_announced:
                self.walkable_announced = True
                return LABEL_MESSAGES["walkable"]["tengah"]

        return None


# ── LabelCooldownTracker ─────────────────────────────────────

class LabelCooldownTracker:
    def __init__(self):
        self._state = {}

    def should_announce(self, label, position):
        cooldown = COOLDOWN_BY_LABEL.get(label, 5)
        if cooldown == NO_COOLDOWN:
            return True

        now   = time.time()
        state = self._state.get(label)

        if state is None:
            self._state[label] = {"last_time": now, "last_position": position}
            return True

        if state["last_position"] != position:
            self._state[label] = {"last_time": now, "last_position": position}
            return True

        if now - state["last_time"] >= cooldown:
            self._state[label] = {"last_time": now, "last_position": position}
            return True

        return False

    def reset(self, label):
        self._state.pop(label, None)


# ── Fungsi deteksi ───────────────────────────────────────────

def get_box_position(x1, x2, frame_width):
    center_x = (x1 + x2) / 2
    if center_x < frame_width / 3:
        return "kiri"
    if center_x < (2 * frame_width / 3):
        return "tengah"
    return "kanan"


def get_all_detections(result, frame_width):
    detections = {}

    if result.boxes is None or len(result.boxes) == 0:
        return []

    for box in result.boxes:
        confidence = float(box.conf[0])
        if confidence < CONF_THRESHOLD:
            continue

        class_id = int(box.cls[0])
        label    = result.names.get(class_id, str(class_id))
        label = label.replace(" ", "")

        x1, y1, x2, y2 = box.xyxy[0].tolist()
        position = get_box_position(x1, x2, frame_width)

        key = (label, position)
        if key not in detections or confidence > detections[key]["confidence"]:
            detections[key] = {
                "label":      label,
                "confidence": round(confidence, 2),
                "position":   position,
            }

    return sorted(
        detections.values(),
        key=lambda d: LABEL_PRIORITY.get(d["label"], 99),
    )


def _build_vehicle_summary(vehicle_detections):
    """
    Gabungkan beberapa deteksi kendaraan/orang jadi satu kalimat ringkas.

    Contoh:
      car-kiri + motorcycle-kanan → "Ada mobil di kiri dan motor di kanan, waspada."
      car-kiri + car-kanan        → "Ada mobil di kiri dan kanan, waspada."
      person-tengah + car-kiri    → "Ada orang di depan dan mobil di kiri, waspada."
      car-tengah saja             → "Ada mobil di depan, waspada."
    """
    if not vehicle_detections:
        return None

    # Kumpulkan per label → set posisi
    by_label = {}
    for det in vehicle_detections:
        label = det["label"]
        pos   = det["position"]
        by_label.setdefault(label, set()).add(pos)

    # Buat fragmen per label+posisi
    # Urutan posisi: tengah > kiri > kanan (paling kritis duluan)
    POS_ORDER = {"tengah": 0, "kiri": 1, "kanan": 2}
    POS_WORD  = {"tengah": "depan", "kiri": "kiri", "kanan": "kanan"}

    fragments = []
    # Urutkan label berdasarkan prioritas
    sorted_labels = sorted(by_label.keys(), key=lambda l: LABEL_PRIORITY.get(l, 99))

    for label in sorted_labels:
        positions = sorted(by_label[label], key=lambda p: POS_ORDER.get(p, 9))
        name      = LABEL_NAMES.get(label, label)
        pos_words = [POS_WORD.get(p, p) for p in positions]

        if len(pos_words) == 1:
            fragments.append(f"{name} di {pos_words[0]}")
        else:
            fragments.append(f"{name} di {' dan '.join(pos_words)}")

    if not fragments:
        return None

    if len(fragments) == 1:
        sentence = f"Ada {fragments[0]}, waspada."
    elif len(fragments) == 2:
        sentence = f"Ada {fragments[0]} dan {fragments[1]}, waspada."
    else:
        sentence = f"Ada {', '.join(fragments[:-1])}, dan {fragments[-1]}, waspada."

    return sentence


def build_tts_messages(detections, center_zone_tracker, cooldown_tracker):
    """
    Buat list pesan TTS dari semua deteksi frame ini.

    Logika:
      - road/walkable tengah       → CenterZoneTracker (anti-flicker)
      - road kiri/kanan            → diabaikan
      - walkable kiri/kanan        → langsung (petunjuk arah kembali)
      - bahaya statis (pothole, obstacle, stair, puddle, zebracross) → per posisi
      - kendaraan/orang (vehicle)  → digabung jadi SATU kalimat ringkas
    """
    messages = []

    # Reset cooldown label yang hilang dari frame
    detected_labels = {d["label"] for d in detections}
    for label in list(cooldown_tracker._state.keys()):
        if label not in detected_labels:
            cooldown_tracker.reset(label)

    # Handle road/walkable tengah via voting
    center_rw_label = None
    for det in detections:
        if det["label"] in ("road", "walkable") and det["position"] == "tengah":
            if center_rw_label is None or LABEL_PRIORITY[det["label"]] < LABEL_PRIORITY[center_rw_label]:
                center_rw_label = det["label"]

    center_msg = center_zone_tracker.update(center_rw_label)
    if center_msg:
        messages.append(center_msg)

    # Pisahkan deteksi: bahaya statis vs kendaraan/orang
    static_detections  = []
    vehicle_detections = []

    for det in detections:
        label    = det["label"]
        position = det["position"]

        # Sudah dihandle tracker
        if label in ("road", "walkable") and position == "tengah":
            continue

        # road kiri/kanan → abaikan
        if label == "road" and position in ("kiri", "kanan"):
            continue

        if label in VEHICLE_LABELS:
            # Cek cooldown untuk kendaraan
            if cooldown_tracker.should_announce(label, position):
                vehicle_detections.append(det)
        else:
            static_detections.append(det)

    # Proses bahaya statis (pothole, obstacle, stair, puddle, zebracross, walkable kiri/kanan)
    for det in static_detections:
        label    = det["label"]
        position = det["position"]

        if not cooldown_tracker.should_announce(label, position):
            continue

        template = LABEL_MESSAGES.get(label, {})
        msg      = template.get(position, "")
        if msg:
            messages.append(msg)

    # Proses kendaraan/orang → satu kalimat gabungan
    if vehicle_detections:
        summary = _build_vehicle_summary(vehicle_detections)
        if summary:
            messages.append(summary)

    return messages


def _has_center_threat(detections):
    for det in detections:
        if det["position"] == "tengah" and det["label"] not in ("road", "walkable"):
            return True
    return False


def build_navigation_message(status, decision, detections, center_zone_tracker, cooldown_tracker):
    """
    Gabungkan pesan sensor ultrasonik + semua pesan ML.

    Prinsip integrasi:
    - SILENT saat benar-benar aman (tidak ada ML, ultrasonik safe)
    - ML mendeskripsikan OBJEK, ultrasonik memberi SARAN ARAH
    - Tidak ada duplikasi antara keduanya
    - Kendaraan kiri+kanan digabung jadi satu kalimat
    """
    tts_parts     = build_tts_messages(detections, center_zone_tracker, cooldown_tracker)
    has_ml        = bool(tts_parts)
    center_threat = _has_center_threat(detections)

    # ── Ultrasonik danger ────────────────────────────────────
    if status == "danger":
        if decision == "STOP":
            sensor_msg = "Bahaya, hambatan sangat dekat. Berhenti."
        elif decision == "KIRI":
            sensor_msg = "Bahaya, hambatan di depan. Arah kiri lebih aman."
        elif decision == "KANAN":
            sensor_msg = "Bahaya, hambatan di depan. Arah kanan lebih aman."
        else:
            sensor_msg = "Bahaya, hambatan dekat."

    # ── Ultrasonik warning ───────────────────────────────────
    elif status == "warning":
        if has_ml:
            # ML sudah sebut objeknya, sensor cukup beri saran arah
            if decision == "KIRI":
                sensor_msg = "Disarankan belok kiri."
            elif decision == "KANAN":
                sensor_msg = "Disarankan belok kanan."
            elif decision == "STOP":
                sensor_msg = "Berhenti sementara."
            else:
                sensor_msg = "Tetap berhati-hati."
        else:
            if decision == "KIRI":
                sensor_msg = "Hambatan terdeteksi. Disarankan belok kiri."
            elif decision == "KANAN":
                sensor_msg = "Hambatan terdeteksi. Disarankan belok kanan."
            elif decision == "STOP":
                sensor_msg = "Hambatan terdeteksi. Berhenti sementara."
            else:
                sensor_msg = "Hambatan terdeteksi, tetap berhati-hati."

    # ── Ultrasonik safe ──────────────────────────────────────
    else:
        if not has_ml:
            # Benar-benar aman → SILENT
            sensor_msg = None
        else:
            # Ada ML → biarkan ML yang bicara, tidak perlu sensor_msg
            sensor_msg = None

    parts = ([sensor_msg] if sensor_msg else []) + tts_parts
    return " ".join(parts)
# ════════════════════════════════════════════════════════════
# BLUETOOTH GATT CLASSES
# ════════════════════════════════════════════════════════════

class AutoPairAgent(dbus.service.Object):
    def __init__(self, bus):
        super().__init__(bus, AGENT_PATH)
        self.bus = bus

    @dbus.service.method(AGENT_IFACE, in_signature="", out_signature="")
    def Release(self):
        print("Agent released")

    @dbus.service.method(AGENT_IFACE, in_signature="o", out_signature="s")
    def RequestPinCode(self, device):
        print("RequestPinCode:", device)
        set_device_trusted(self.bus, device)
        return BLUETOOTH_FALLBACK_PIN

    @dbus.service.method(AGENT_IFACE, in_signature="o", out_signature="u")
    def RequestPasskey(self, device):
        print("RequestPasskey:", device)
        set_device_trusted(self.bus, device)
        return dbus.UInt32(0)

    @dbus.service.method(AGENT_IFACE, in_signature="ouq", out_signature="")
    def DisplayPasskey(self, device, passkey, entered):
        print("DisplayPasskey:", device, passkey, entered)

    @dbus.service.method(AGENT_IFACE, in_signature="os", out_signature="")
    def DisplayPinCode(self, device, pincode):
        print("DisplayPinCode:", device, pincode)

    @dbus.service.method(AGENT_IFACE, in_signature="ou", out_signature="")
    def RequestConfirmation(self, device, passkey):
        print("RequestConfirmation auto-accepted:", device, passkey)
        set_device_trusted(self.bus, device)

    @dbus.service.method(AGENT_IFACE, in_signature="o", out_signature="")
    def RequestAuthorization(self, device):
        print("RequestAuthorization auto-accepted:", device)
        set_device_trusted(self.bus, device)

    @dbus.service.method(AGENT_IFACE, in_signature="os", out_signature="")
    def AuthorizeService(self, device, uuid):
        print("AuthorizeService auto-accepted:", device, uuid)
        set_device_trusted(self.bus, device)

    @dbus.service.method(AGENT_IFACE, in_signature="", out_signature="")
    def Cancel(self):
        print("Agent request cancelled")


class Application(dbus.service.Object):
    def __init__(self, bus):
        self.path = APP_PATH
        self.services = []
        super().__init__(bus, self.path)

    def get_path(self):
        return dbus.ObjectPath(self.path)

    def add_service(self, service):
        self.services.append(service)

    @dbus.service.method(DBUS_OM_IFACE, out_signature="a{oa{sa{sv}}}")
    def GetManagedObjects(self):
        response = {}
        for service in self.services:
            response[service.get_path()] = service.get_properties()
            for characteristic in service.characteristics:
                response[characteristic.get_path()] = characteristic.get_properties()
        return response


class Service(dbus.service.Object):
    PATH_BASE = APP_PATH + "/service"

    def __init__(self, bus, index, uuid, primary):
        self.path = self.PATH_BASE + str(index)
        self.bus = bus
        self.uuid = uuid
        self.primary = primary
        self.characteristics = []
        super().__init__(bus, self.path)

    def get_properties(self):
        return {
            GATT_SERVICE_IFACE: {
                "UUID": self.uuid,
                "Primary": self.primary,
                "Characteristics": dbus.Array(
                    [c.get_path() for c in self.characteristics],
                    signature="o",
                ),
            }
        }

    def get_path(self):
        return dbus.ObjectPath(self.path)

    def add_characteristic(self, characteristic):
        self.characteristics.append(characteristic)

    @dbus.service.method(DBUS_PROP_IFACE, in_signature="s", out_signature="a{sv}")
    def GetAll(self, interface):
        if interface != GATT_SERVICE_IFACE:
            raise dbus.exceptions.DBusException("Invalid interface")
        return self.get_properties()[GATT_SERVICE_IFACE]


class Characteristic(dbus.service.Object):
    def __init__(self, bus, index, uuid, flags, service):
        self.path = service.path + "/char" + str(index)
        self.bus = bus
        self.uuid = uuid
        self.flags = flags
        self.service = service
        super().__init__(bus, self.path)

    def get_properties(self):
        return {
            GATT_CHRC_IFACE: {
                "Service": self.service.get_path(),
                "UUID": self.uuid,
                "Flags": dbus.Array(self.flags, signature="s"),
            }
        }

    def get_path(self):
        return dbus.ObjectPath(self.path)

    @dbus.service.method(DBUS_PROP_IFACE, in_signature="s", out_signature="a{sv}")
    def GetAll(self, interface):
        if interface != GATT_CHRC_IFACE:
            raise dbus.exceptions.DBusException("Invalid interface")
        return self.get_properties()[GATT_CHRC_IFACE]

    @dbus.service.method(GATT_CHRC_IFACE, in_signature="a{sv}", out_signature="ay")
    def ReadValue(self, options):
        return dbus.Array([], signature="y")

    @dbus.service.method(GATT_CHRC_IFACE, in_signature="aya{sv}", out_signature="")
    def WriteValue(self, value, options):
        print("WriteValue default:", bytes(value))

    @dbus.service.method(GATT_CHRC_IFACE, in_signature="", out_signature="")
    def StartNotify(self):
        pass

    @dbus.service.method(GATT_CHRC_IFACE, in_signature="", out_signature="")
    def StopNotify(self):
        pass

    @dbus.service.signal(DBUS_PROP_IFACE, signature="sa{sv}as")
    def PropertiesChanged(self, interface, changed, invalidated):
        pass


class SensorCharacteristic(Characteristic):
    def __init__(self, bus, index, service):
        super().__init__(
            bus, index, SENSOR_CHARACTERISTIC_UUID,
            ["read", "notify"], service,
        )
        self.notifying = False
        self.last_payload = json.dumps(
            {"d": 0, "s": "safe", "m": "Menunggu data sensor", "t": int(time.time() * 1000)},
            separators=(",", ":"),
        )
        self.pending_payload = None

    def ReadValue(self, options):
        return dbus.Array(bytearray(self.last_payload.encode("utf-8")), signature="y")

    def StartNotify(self):
        if self.notifying:
            return
        self.notifying = True
        print("Flutter connected / notify started")
        if self.pending_payload is not None:
            payload = self.pending_payload
            self.pending_payload = None
            GLib.idle_add(self.notify_text, payload)

    def StopNotify(self):
        self.notifying = False
        print("Flutter disconnected / notify stopped")

    def notify_text(self, payload):
        self.last_payload = payload
        if not self.notifying:
           self.pending_payload = payload
           print("BLE notify ditunda, Flutter belum subscribe:", payload)
           return False

        encoded = payload.encode("utf-8")
        print(f"[NOTIFY_TS={time.time():.3f}] BLE notify:", payload)   # ← tambah timestamp

        for start in range(0, len(encoded), NOTIFY_CHUNK_BYTES):
           chunk = encoded[start:start + NOTIFY_CHUNK_BYTES]
           self.PropertiesChanged(
              GATT_CHRC_IFACE,
              {"Value": dbus.Array(bytearray(chunk), signature="y")},
              [],
           )

        return False

class PairingCharacteristic(Characteristic):
    def __init__(self, bus, index, service):
        super().__init__(
            bus, index, PAIRING_CHARACTERISTIC_UUID,
            ["read", "write"], service,
        )
        self.last_response = "READY"

    def ReadValue(self, options):
        return dbus.Array(bytearray(self.last_response.encode("utf-8")), signature="y")

    def WriteValue(self, value, options):
        text = bytes(value).decode("utf-8", errors="replace").strip()
        print("Pairing payload:", text)

        device_id = ""
        pin = ""

        try:
            if text.startswith("{"):
                payload = json.loads(text)
                device_id = str(payload.get("deviceId", "")).strip()
                pin = str(payload.get("pin", "")).strip()
            elif "|" in text:
                device_id, pin = text.split("|", 1)
                device_id = device_id.strip()
                pin = pin.strip()
        except Exception as error:
            print("Pairing payload parse error:", error)

        if device_id != DEVICE_ID:
            self.last_response = "ERR_DEVICE"
            print("Pairing rejected: kode tongkat salah")
            return

        if pin != DEVICE_PIN:
            self.last_response = "ERR_PIN"
            print("Pairing rejected: PIN salah")
            return

        state = load_state()
        authorized = state.get("authorizedPhones", [])
        authorized.append({"pairedAt": int(time.time()), "source": "ble"})
        state["authorizedPhones"] = authorized[-5:]
        state["deviceId"] = DEVICE_ID
        save_state(state)

        self.last_response = "OK"
        print("Application PIN pairing success:", DEVICE_ID)

class IMUCharacteristic(Characteristic):
    def __init__(self, bus, index, service):
        super().__init__(
            bus, index, IMU_CHARACTERISTIC_UUID,
            ["write-without-response"], service,
        )

    def WriteValue(self, value, options):
        pass

class TemanArahService(Service):
    def __init__(self, bus, index):
        super().__init__(bus, index, SERVICE_UUID, True)
        self.sensor_characteristic  = SensorCharacteristic(bus, 0, self)
        self.pairing_characteristic = PairingCharacteristic(bus, 1, self)
        self.imu_characteristic     = IMUCharacteristic(bus, 2, self)
        self.add_characteristic(self.sensor_characteristic)
        self.add_characteristic(self.pairing_characteristic)
        self.add_characteristic(self.imu_characteristic)


class Advertisement(dbus.service.Object):
    def __init__(self, bus, index):
        self.path = ADV_PATH
        self.bus = bus
        self.ad_type = "peripheral"
        self.service_uuids = [SERVICE_UUID]
        self.local_name = DEVICE_NAME
        self.include_tx_power = True
        super().__init__(bus, self.path)

    def get_path(self):
        return dbus.ObjectPath(self.path)

    def get_properties(self):
        return {
            LE_ADVERTISEMENT_IFACE: {
                "Type": self.ad_type,
                "ServiceUUIDs": dbus.Array(self.service_uuids, signature="s"),
                "LocalName": dbus.String(self.local_name),
                "Includes": dbus.Array(["tx-power"], signature="s"),
            }
        }

    @dbus.service.method(DBUS_PROP_IFACE, in_signature="s", out_signature="a{sv}")
    def GetAll(self, interface):
        if interface != LE_ADVERTISEMENT_IFACE:
            raise dbus.exceptions.DBusException("Invalid interface")
        return self.get_properties()[LE_ADVERTISEMENT_IFACE]

    @dbus.service.method(LE_ADVERTISEMENT_IFACE, in_signature="", out_signature="")
    def Release(self):
        print("Advertisement released")


# ════════════════════════════════════════════════════════════
# THREAD LISTENERS
# ════════════════════════════════════════════════════════════

def start_button_listener(sensor_characteristic):
    global _button_thread_started
    if _button_thread_started:
        return
    _button_thread_started = True

    # FIX: GPIO.setmode hanya di sini, tidak duplikat di start_detection_listener
    GPIO.setmode(GPIO.BCM)
    GPIO.setwarnings(False)
    GPIO.setup(SOS_BUTTON, GPIO.IN, pull_up_down=GPIO.PUD_UP)

    def send_ble_event(payload):
        GLib.idle_add(sensor_characteristic.notify_text, payload)

    def worker():
        click_count = 0
        last_click_time = 0
        print("Button listener aktif di GPIO", SOS_BUTTON)

        while _background_running:
            if GPIO.input(SOS_BUTTON) == 0:
                press_time = time.time()
                voice_active = False

                while GPIO.input(SOS_BUTTON) == 0 and _background_running:
                    if time.time() - press_time >= 2 and not voice_active:
                        voice_active = True
                        print("VOICE ASSISTANT AKTIF!")
                        send_ble_event('{"e":"va_down"}')
                    time.sleep(0.05)

                if voice_active:
                    print("VOICE ASSISTANT NONAKTIF!")
                    send_ble_event('{"e":"va_up"}')
                    click_count = 0
                    time.sleep(0.2)
                    continue

                current_time = time.time()
                if current_time - last_click_time < 1:
                    click_count += 1
                else:
                    click_count = 1
                last_click_time = current_time
                print(f"Jumlah klik: {click_count}")

                # FIX: >= 3 bukan > 3 agar tepat 3 klik = SOS
                if click_count >= 3:
                    print("SOS AKTIF!")
                    send_ble_event('{"e":"sos"}')
                    click_count = 0

                time.sleep(0.2)
            time.sleep(0.05)

    threading.Thread(target=worker, daemon=True).start()


def start_battery_listener(sensor_characteristic):
    global _battery_thread_started
    if _battery_thread_started:
        return
    _battery_thread_started = True

    def worker():
        try:
            i2c_bus = I2C(board.SCL, board.SDA)
            ina219  = INA219(i2c_bus)
            print("Battery listener aktif dengan INA219")
        except Exception as error:
            print("Gagal inisialisasi INA219:", error)
            return

        while _background_running:
            try:
                voltage = ina219.bus_voltage
                current = ina219.current
                power   = ina219.power

                smooth   = smooth_voltage(voltage)
                battery  = round_to_nearest_5(battery_percentage(smooth))

                payload = json.dumps(
                    {"b": battery, "v": round(smooth, 2), "t": int(time.time() * 1000)},
                    separators=(",", ":"),
                )
                GLib.idle_add(sensor_characteristic.notify_text, payload)

                print("===== BATTERY MONITOR =====")
                print(f"Voltage raw : {voltage:.2f} V")
                print(f"Voltage avg : {smooth:.2f} V")
                print(f"Current     : {current:.2f} mA")
                print(f"Power       : {power:.2f} mW")
                print(f"Battery UI  : {battery} %")
                if battery <= 20:
                    print("WARNING: LOW BATTERY!")
                print("-----------------------------")

            except Exception as error:
                print("Gagal membaca baterai:", error)

            time.sleep(5)

    threading.Thread(target=worker, daemon=True).start()


def start_detection_listener(sensor_characteristic):
    global _detection_thread_started
    if _detection_thread_started:
        return
    _detection_thread_started = True

    # FIX: tidak memanggil GPIO.setmode lagi (sudah di start_button_listener)
    GPIO.setwarnings(False)
    for trig, echo in [
        (TRIG_CENTER, ECHO_CENTER),
        (TRIG_LEFT,   ECHO_LEFT),
        (TRIG_RIGHT,  ECHO_RIGHT),
    ]:
        GPIO.setup(trig, GPIO.OUT)
        GPIO.setup(echo, GPIO.IN)
        GPIO.output(trig, False)

    def worker():
        try:
            from picamera2 import Picamera2
            from ultralytics import YOLO

            model_custom = YOLO("best.onnx")

            camera = Picamera2()
            camera.preview_configuration.main.size = (512, 512)
            camera.preview_configuration.main.format = "RGB888"
            camera.configure("preview")
            camera.start()

            print("Detection listener aktif: ultrasonic + YOLO")
            time.sleep(1)
        except Exception as error:
            print("Gagal inisialisasi kamera/model ML:", error)
            return

        center_zone_tracker = CenterZoneTracker()
        cooldown_tracker    = LabelCooldownTracker()

        while _background_running:
            try:
                center = read_stable_distance(TRIG_CENTER, ECHO_CENTER, samples=3)
                left   = read_stable_distance(TRIG_LEFT,   ECHO_LEFT,   samples=3)
                right  = read_stable_distance(TRIG_RIGHT,  ECHO_RIGHT,  samples=3)

                decision = decide_direction(left, center, right)
                status   = status_from_distance(center)

                frame   = camera.capture_array()
                t_infer_start = time.time()
                results = model_custom(frame, verbose=False)
                t_infer_end = time.time()
                print(f"[INFERENCE_TIME] {(t_infer_end - t_infer_start) * 1000:.1f} ms")

                frame_width = frame.shape[1]
                detections  = get_all_detections(results[0], frame_width)

                message = build_navigation_message(
                    status, decision, detections,
                    center_zone_tracker, cooldown_tracker,
                )

                payload = {
                    "d":        round(safe_distance(center), 1),
                    "s":        status,
                    "m":        message,
                    "left":     round(safe_distance(left),   1),
                    "center":   round(safe_distance(center), 1),
                    "right":    round(safe_distance(right),  1),
                    "decision": compact_direction(decision),
                    "t":        int(time.time() * 1000)
                }

                if detections:
                    payload["detections"] = [
                        {"label": d["label"], "pos": d["position"], "conf": d["confidence"]}
                        for d in detections
                    ]

                text = json.dumps(payload, separators=(",", ":"))
                GLib.idle_add(sensor_characteristic.notify_text, text)

                print("===== SENSOR + ML =====")
                print(f"Kiri    : {safe_distance(left):.1f} cm")
                print(f"Tengah  : {safe_distance(center):.1f} cm")
                print(f"Kanan   : {safe_distance(right):.1f} cm")
                print(f"Status  : {status} | Arah: {decision}")
                print(f"Deteksi : {[(d['label'], d['position'], d['confidence']) for d in detections]}")
                print(f"Pesan   : {message}")
                print("-----------------------")

            except Exception as error:
                print("Gagal membaca sensor/ML:", error)

            time.sleep(1)

    threading.Thread(target=worker, daemon=True).start()


# ════════════════════════════════════════════════════════════
# MAIN
# ════════════════════════════════════════════════════════════

def register_agent(bus):
    agent   = AutoPairAgent(bus)
    manager = dbus.Interface(
        bus.get_object(BLUEZ_SERVICE_NAME, "/org/bluez"),
        AGENT_MANAGER_IFACE,
    )
    manager.RegisterAgent(AGENT_PATH, "NoInputNoOutput")
    manager.RequestDefaultAgent(AGENT_PATH)
    print("Auto pairing agent aktif")
    return agent


def main():
    global _background_running

    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)

    bus          = dbus.SystemBus()
    adapter_path = find_adapter(bus)

    register_agent(bus)

    app               = Application(bus)
    temanarah_service = TemanArahService(bus, 0)
    app.add_service(temanarah_service)

    start_button_listener(temanarah_service.sensor_characteristic)
    start_battery_listener(temanarah_service.sensor_characteristic)
    start_detection_listener(temanarah_service.sensor_characteristic)
    start_fall_detection_listener(temanarah_service.sensor_characteristic)

    service_manager = dbus.Interface(
        bus.get_object(BLUEZ_SERVICE_NAME, adapter_path),
        GATT_MANAGER_IFACE,
    )

    advertisement     = Advertisement(bus, 0)
    advertising_manager = dbus.Interface(
        bus.get_object(BLUEZ_SERVICE_NAME, adapter_path),
        LE_ADVERTISING_MANAGER_IFACE,
    )

    mainloop = GLib.MainLoop()

    service_manager.RegisterApplication(
        app.get_path(), {},
        reply_handler=lambda: print("GATT app registered"),
        error_handler=lambda e: (print("GATT app register failed:", e), mainloop.quit()),
    )

    advertising_manager.RegisterAdvertisement(
        advertisement.get_path(), {},
        reply_handler=lambda: print("BLE peripheral aktif:", DEVICE_NAME),
        error_handler=lambda e: (print("Advertisement register failed:", e), mainloop.quit()),
    )

    try:
        mainloop.run()
    finally:
        _background_running = False
        GPIO.cleanup()


if __name__ == "__main__":
    main()