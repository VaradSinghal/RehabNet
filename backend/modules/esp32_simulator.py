"""
ESP32 Simulator
Simulates realistic MPU6050 accelerometer data with Parkinson's-like
resting tremor (4-7 Hz) superimposed on Gaussian noise.
Plug real ESP32 here later by replacing generate_sample() with
a serial/WebSocket read from the physical device.
"""

import time
import math
import random
import threading


class ESP32Simulator:
    def __init__(self, emit_callback, interval_s: float = 0.1):
        """
        :param emit_callback: callable(data_dict) called on each sample
        :param interval_s:    sampling interval in seconds (default 100 ms → 10 Hz)
        """
        self._emit = emit_callback
        self._interval = interval_s
        self._running = False
        self._thread: threading.Thread | None = None

        # Tremor parameters (will drift slightly over time to feel realistic)
        self._tremor_freq = 5.0   # Hz  (Parkinson's resting tremor range: 4-7 Hz)
        self._tremor_amp  = 0.6   # g   (moderate)
        self._phase       = 0.0

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------
    def start(self):
        if self._running:
            return
        self._running = True
        self._thread = threading.Thread(target=self._loop, daemon=True)
        self._thread.start()

    def stop(self):
        self._running = False
        if self._thread:
            self._thread.join(timeout=2)

    # ------------------------------------------------------------------
    # Internal
    # ------------------------------------------------------------------
    def _loop(self):
        t = 0.0
        while self._running:
            sample = self._generate_sample(t)
            self._emit(sample)
            t += self._interval
            time.sleep(self._interval)

            # Slowly drift tremor frequency to feel realistic
            self._tremor_freq += random.uniform(-0.02, 0.02)
            self._tremor_freq = max(4.0, min(7.0, self._tremor_freq))

    def _generate_sample(self, t: float) -> dict:
        """Generate one MPU6050-like data packet."""
        # Primary tremor axis (X)
        noise_x = random.gauss(0, 0.05)
        noise_y = random.gauss(0, 0.05)
        noise_z = random.gauss(0, 0.03)

        ax = self._tremor_amp * math.sin(2 * math.pi * self._tremor_freq * t) + noise_x
        ay = self._tremor_amp * 0.4 * math.sin(2 * math.pi * self._tremor_freq * t + math.pi / 6) + noise_y
        az = 1.0 + self._tremor_amp * 0.2 * math.sin(2 * math.pi * self._tremor_freq * t + math.pi / 3) + noise_z  # gravity offset

        # Tremor intensity: RMS of 3-axis, scaled 0-100
        rms = math.sqrt(ax ** 2 + ay ** 2 + (az - 1.0) ** 2)
        intensity = min(100.0, round(rms * 60, 2))

        return {
            "timestamp": round(t, 3),
            "accelerometer_x": round(ax, 4),
            "accelerometer_y": round(ay, 4),
            "accelerometer_z": round(az, 4),
            "tremor_intensity": intensity,
            "tremor_freq_hz": round(self._tremor_freq, 2),
        }
