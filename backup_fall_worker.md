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

imu_cane_buffer = collections.deque(maxlen=FALL_BUFFER_SIZE)
imu_buffer_lock = threading.Lock()
_running = True

def load_model():
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
        cps  = [c for c in algo.predict(pen=10) if c < len(signal)]
        if not cps:
            return None
        costs = []
        for cp in cps:
            before = signal[max(0, cp-10):cp]
            after  = signal[cp:min(len(signal), cp+10)]
            costs.append(abs(after.mean() - before.mean()) if len(before) and len(after) else 0)
        return cps[np.argmax(costs)]
    except Exception:
        return None

def detect_fall(buf_cane, model):
    arr  = np.array(buf_cane)
    mag  = np.nan_to_num(np.sqrt((arr[:, :3] ** 2).sum(axis=1)))
    cp   = get_main_cp(mag)
    if cp is None:
        return False, 0.0
    s, e = cp - WINDOW, cp + WINDOW
    if s < 0 or e > len(arr):
        return False, 0.0
    win   = arr[s:e]
    fused = np.concatenate([win, win], axis=1)[np.newaxis].astype(np.float32)
    prob  = float(model.predict(fused, verbose=0)[0][0])
    return prob > 0.5, prob

def main():
    model = load_model()
    if model is None:
        return

    threading.Thread(target=read_mpu6050, daemon=True).start()

    while _running:
        with imu_buffer_lock:
            buf = list(imu_cane_buffer)

        if len(buf) >= FALL_BUFFER_SIZE:
            is_fall, prob = detect_fall(buf, model)
            if is_fall:
                # Kirim ke parent process via stdout
                print(json.dumps({"e": "fall", "prob": round(prob, 2),  "t": int(time.time() * 1000)}), flush=True)

        time.sleep(1)

if __name__ == "__main__":
    main()