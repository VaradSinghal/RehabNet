"""
Tremor Analyzer
Accepts a sliding window of accelerometer samples and computes:
  - Dominant tremor frequency (Hz) via NumPy FFT
  - RMS vibration amplitude
  - Tremor severity score (0-100)
  - Severity label: Low / Moderate / High
"""

import numpy as np
from collections import deque


SAMPLE_RATE = 10       # Hz — must match ESP32 emit rate
WINDOW_SIZE = 64       # samples (~6.4 s at 10 Hz)

SEVERITY_THRESHOLDS = {
    "Low":      (0,   30),
    "Moderate": (30,  65),
    "High":     (65, 100),
}


class TremorAnalyzer:
    def __init__(self, sample_rate: int = SAMPLE_RATE, window: int = WINDOW_SIZE):
        self._fs = sample_rate
        self._window = window
        self._buf_x: deque[float] = deque(maxlen=window)
        self._buf_y: deque[float] = deque(maxlen=window)
        self._buf_z: deque[float] = deque(maxlen=window)

    # ------------------------------------------------------------------
    def add_sample(self, ax: float, ay: float, az: float):
        self._buf_x.append(ax)
        self._buf_y.append(ay)
        self._buf_z.append(az - 1.0)   # remove gravity

    def analyse(self) -> dict:
        if len(self._buf_x) < self._window // 2:
            return self._empty_result()

        x = np.array(self._buf_x)
        y = np.array(self._buf_y)
        z = np.array(self._buf_z)

        # Use magnitude vector for frequency analysis
        magnitude = np.sqrt(x**2 + y**2 + z**2)

        freq_hz, amplitude = self._dominant_frequency(magnitude)
        rms = float(np.sqrt(np.mean(magnitude ** 2)))
        score = self._severity_score(freq_hz, rms)
        label = self._classify(score)

        return {
            "dominant_freq_hz": round(freq_hz, 2),
            "amplitude_rms": round(rms, 4),
            "severity_score": round(score, 1),
            "severity_label": label,
        }

    # ------------------------------------------------------------------
    def _dominant_frequency(self, signal: np.ndarray) -> tuple[float, float]:
        """Return (dominant_Hz, amplitude) using FFT."""
        n = len(signal)
        window = np.hanning(n)
        fft_vals = np.abs(np.fft.rfft(signal * window))
        freqs = np.fft.rfftfreq(n, d=1.0 / self._fs)

        # Only look in 1-12 Hz (tremor range)
        mask = (freqs >= 1.0) & (freqs <= 12.0)
        if not np.any(mask):
            return 0.0, 0.0

        idx = np.argmax(fft_vals[mask])
        dominant_freq = float(freqs[mask][idx])
        amplitude = float(fft_vals[mask][idx]) / (n / 2)
        return dominant_freq, amplitude

    def _severity_score(self, freq_hz: float, rms: float) -> float:
        """Score 0-100 combining frequency proximity to Parkinson's range + amplitude."""
        # Frequency score: peaks at 4-7 Hz
        if 4.0 <= freq_hz <= 7.0:
            freq_score = 100.0
        elif freq_hz < 4.0:
            freq_score = max(0, (freq_hz / 4.0) * 80)
        else:
            freq_score = max(0, 100 - (freq_hz - 7.0) * 20)

        # Amplitude score
        amp_score = min(100.0, rms * 120)

        return (freq_score * 0.4) + (amp_score * 0.6)

    @staticmethod
    def _classify(score: float) -> str:
        if score < 30:
            return "Low"
        elif score < 65:
            return "Moderate"
        return "High"

    @staticmethod
    def _empty_result() -> dict:
        return {
            "dominant_freq_hz": 0.0,
            "amplitude_rms": 0.0,
            "severity_score": 0.0,
            "severity_label": "Low",
        }
