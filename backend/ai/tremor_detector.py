import numpy as np
from scipy.fft import rfft, rfftfreq

class TremorDetector:
    def __init__(self, sampling_rate_hz: int = 50, window_size: int = 256):
        self.sampling_rate = sampling_rate_hz
        self.window_size = window_size
        self.timestamps = []
        self.ax_buf = []
        self.ay_buf = []
        self.az_buf = []

    def process_sample(self, ax: float, ay: float, az: float, timestamp: int) -> dict:
        """
        Takes a single sample from the ESP32. Returns a dict with frequency 
        and severity if the window is full, otherwise returns None.
        """
        self.ax_buf.append(ax)
        self.ay_buf.append(ay)
        self.az_buf.append(az)
        self.timestamps.append(timestamp)

        # Maintain sliding window size
        if len(self.ax_buf) > self.window_size:
            self.ax_buf.pop(0)
            self.ay_buf.pop(0)
            self.az_buf.pop(0)
            self.timestamps.pop(0)

        # Only analyze if we have enough data (buffer at least 50% full to start)
        if len(self.ax_buf) >= self.window_size // 2:
            return self._analyze()
        return {
             "frequency_hz": 0.0,
             "amplitude_g": 0.0,
             "severity": "Collecting Data..."
        }

    def _analyze(self) -> dict:
        """Applies FFT to extract dominant frequency and calculate severity."""
        a_x = np.array(self.ax_buf)
        a_y = np.array(self.ay_buf)
        a_z = np.array(self.az_buf)

        # Magnitude (remove constant 1g gravity offset via mean subtraction)
        a_x = a_x - np.mean(a_x)
        a_y = a_y - np.mean(a_y)
        a_z = a_z - np.mean(a_z)
        magnitude = np.sqrt(a_x**2 + a_y**2 + a_z**2)

        # Fast Fourier Transform
        n = len(magnitude)
        yf = rfft(magnitude)
        xf = rfftfreq(n, 1.0 / self.sampling_rate)

        # Ignore DC offset (0Hz)
        yf_abs = np.abs(yf)[1:]
        xf_clean = xf[1:]

        if len(yf_abs) == 0:
            return {"frequency_hz": 0.0, "amplitude_g": 0.0, "severity": "Low"}

        # Peak frequency
        peak_idx = np.argmax(yf_abs)
        dominant_freq = xf_clean[peak_idx]

        # RMS Amplitude calculation
        rms_amplitude = np.sqrt(np.mean(magnitude**2))

        # Severity Classifier (Parkinson's resting tremor typically 4-7Hz)
        severity = "Low"
        if 4.0 <= dominant_freq <= 7.0:
            if rms_amplitude > 0.4:
                severity = "High"
            elif rms_amplitude > 0.15:
                severity = "Medium"
        else:
            if rms_amplitude > 0.6: # High generalized motion
                severity = "Medium"

        return {
            "frequency_hz": round(float(dominant_freq), 2),
            "amplitude_g": round(float(rms_amplitude), 4),
            "severity": severity
        }
