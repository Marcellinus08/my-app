```python
#!/usr/bin/env python3
import sys
import json
import time
import threading
import collections
import numpy as np
import ruptures as rpt
import tensorflow as tf
from mpu6050 import mpu6050

FALL_BUFFER_SIZE = 300
WINDOW = 100

# Cooldown setelah deteksi jatuh (detik) — mencegah event duplikat
# dari buffer yang masih berisi data jatuh yang sama.
FALL_COOLDOWN_SEC = 8

# Penalty PELT: semakin tinggi, semakin hanya perubahan drastis yang
# dianggap change point. pen=10 sensitif cukup untuk menangkap jatuh.
PELT_PENALTY = 10

# Minimum delta magnitude di sekitar change point agar dianggap kandidat fall.
# Gerakan normal pegang/jalan biasanya < 1 m/s², jatuh sungguhan > 3 m/s².
MIN_CP_DELTA = 1.0

imu_cane_buffer = collections.deque(maxlen=FALL_BUFFER_SIZE)
imu_buffer_lock = threading.Lock()
_running = True


def load_model():
    # Batasi TF ke 2 thread agar tidak monopoli semua core RPi
    # (mencegah kernel Bluetooth thread starved → BLE disconnect)
    tf.config.threading.set_inter_op_parallelism_threads(2)
    tf.config.threading.set_intra_op_parallelism_threads(2)
    try:
        model = tf.keras.models.load_model("fall_model.h5")
        print("[FALL_WORKER] Model loaded", flush=True)
        return model
    except Exception as e:
        print(f"[FALL_WORKER] Gagal load model: {e}", flush=True)
        return None


def read_mpu6050():
    try:
        sensor = mpu6050(0x68)
        print("[FALL_WORKER] MPU6050 initialized", flush=True)
    except Exception as e:
        print(f"[FALL_WORKER] Gagal init MPU6050: {e}", flush=True)
        return

    while _running:
        try:
            accel = sensor.get_accel_data()
            gyro  = sensor.get_gyro_data()
            with imu_buffer_lock:
                imu_cane_buffer.append([
                    accel['x'], accel['y'], accel['z'],
                    gyro['x'],  gyro['y'],  gyro['z'],
                ])
        except Exception as e:
            print(f"[FALL_WORKER] Error MPU: {e}", flush=True)
        time.sleep(0.01)


def get_main_cp(signal):
    try:
        algo = rpt.Pelt(model="rbf").fit(signal)
        cps  = [c for c in algo.predict(pen=PELT_PENALTY) if c < len(signal)]
        if not cps:
            return None, 0.0
        costs = []
        for cp in cps:
            before = signal[max(0, cp - 10):cp]
            after  = signal[cp:min(len(signal), cp + 10)]
            delta  = abs(after.mean() - before.mean()) if len(before) and len(after) else 0
            costs.append(delta)
        best_idx = int(np.argmax(costs))
        return cps[best_idx], costs[best_idx]
    except Exception:
        return None, 0.0


def detect_fall(buf_cane, model):
    arr = np.array(buf_cane)
    mag = np.nan_to_num(np.sqrt((arr[:, :3] ** 2).sum(axis=1)))
    cp, delta = get_main_cp(mag)

    if cp is None:
        return False, 0.0

    # Tolak change point dengan delta kecil — bukan pola jatuh
    if delta < MIN_CP_DELTA:
        return False, 0.0

    s, e = cp - WINDOW, cp + WINDOW
    if s < 0 or e > len(arr):
        return False, 0.0

    win   = arr[s:e]
    fused = np.concatenate([win, win], axis=1)[np.newaxis].astype(np.float32)
    prob  = float(model.predict(fused, verbose=0)[0][0])
    return prob > 0.5, prob


def main():
    import os
    # Turunkan prioritas proses ini agar tidak bersaing dengan GLib/Bluetooth kernel thread
    try:
        os.nice(5)
    except Exception:
        pass

    model = load_model()
    if model is None:
        return

    threading.Thread(target=read_mpu6050, daemon=True).start()

    last_fall_time = 0.0

    while _running:
        with imu_buffer_lock:
            buf = list(imu_cane_buffer)

        if len(buf) >= FALL_BUFFER_SIZE:
            now = time.time()

            # Lewati deteksi jika masih dalam cooldown
            if now - last_fall_time < FALL_COOLDOWN_SEC:
                time.sleep(1)
                continue

            is_fall, prob = detect_fall(buf, model)
            print(f"[FALL_WORKER] prob={prob:.2f} | fall={is_fall}", flush=True)
            if is_fall:
                last_fall_time = now
                print(
                    json.dumps({
                        "e":    "fall",
                        "prob": round(prob, 2),
                        "t":    int(now * 1000),
                    }),
                    flush=True,
                )

        # 2 detik agar tidak overlap dengan YOLO inference di temanarah.py
        # dan tidak membebani CPU RPi secara bersamaan.
        time.sleep(2)


if __name__ == "__main__":
    main()
```
