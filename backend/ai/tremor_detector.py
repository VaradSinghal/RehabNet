"""
Tremor Detector — Real-time Parkinson's Tremor Analysis Engine
==============================================================

Uses Fast Fourier Transform (FFT) on a sliding window of accelerometer
data from an MPU6050 sensor (via ESP32) to detect and classify resting
tremor, a hallmark symptom of Parkinson's Disease.

Signal Processing Pipeline:
    1. Buffer incoming (ax, ay, az) samples in a sliding window.
    2. Remove DC offset (gravity) by subtracting the per-axis mean.
    3. Compute 3-axis acceleration magnitude.
    4. Apply a Hanning window to minimise spectral leakage.
    5. Run real-valued FFT and extract frequency-domain features.
    6. Isolate the Parkinson's tremor band (3–12 Hz).
    7. Identify dominant frequency and compute spectral energy ratio.
    8. Calculate RMS amplitude.
    9. Classify severity using frequency + amplitude + energy features.
   10. Smooth severity over time with exponential moving average.

Clinical Basis:
    - Parkinson's resting tremor: 4–6 Hz (sometimes up to 8 Hz)
    - Essential tremor: 5–10 Hz (postural / action tremor)
    - Physiological tremor: 8–12 Hz (normal, low amplitude)
    - Reference: Jankovic J. "Parkinson's disease: clinical features and diagnosis."
      J Neurol Neurosurg Psychiatry. 2008;79(4):368-376.
"""

import numpy as np
from scipy.fft import rfft, rfftfreq
from scipy.signal import butter, filtfilt

# ── Constants ────────────────────────────────────────────────────────────────
PARKINSONS_BAND = (3.0, 12.0)   # Hz — range covering PD + essential tremor
SEVERITY_THRESHOLDS = {
    # (min_amplitude_g, min_energy_ratio) → severity
    "High":     (0.30, 0.50),
    "Moderate": (0.10, 0.25),
}
SMOOTHING_ALPHA = 0.3  # EMA alpha for severity score (0 = no update, 1 = instant)


class TremorDetector:
    """
    Stateful per-user tremor detector.  Feed it one sample at a time via
    ``process_sample()``.  Internally maintains a sliding buffer and runs
    analysis once the buffer crosses half-capacity.

    Parameters
    ----------
    sampling_rate_hz : int
        Expected sampling rate of the ESP32 data stream (default 50 Hz).
    window_size : int
        Number of samples in the FFT analysis window (default 256 ≈ 5 s).
    """

    def __init__(self, sampling_rate_hz: int = 50, window_size: int = 256):
        self.sampling_rate = sampling_rate_hz
        self.window_size = window_size

        # Circular buffers
        self.ax_buf: list[float] = []
        self.ay_buf: list[float] = []
        self.az_buf: list[float] = []
        self.timestamps: list[int] = []

        # Smoothed output state
        self._smooth_score: float = 0.0
        self._prev_severity: str = "Low"

        # Pre-compute Butterworth bandpass filter coefficients (3–12 Hz)
        nyquist = self.sampling_rate / 2.0
        low = max(PARKINSONS_BAND[0] / nyquist, 0.01)
        high = min(PARKINSONS_BAND[1] / nyquist, 0.99)
        self._bp_b, self._bp_a = butter(N=4, Wn=[low, high], btype='band')

    # ── Public API ───────────────────────────────────────────────────────
    def process_sample(self, ax: float, ay: float, az: float, timestamp: int) -> dict:
        """
        Ingest a single accelerometer sample.

        Returns a dict with keys:
            - frequency_hz  : dominant tremor frequency (Hz)
            - amplitude_g   : RMS tremor amplitude (g)
            - severity      : 'Low' | 'Moderate' | 'High' | 'Collecting Data...'
            - energy_ratio  : fraction of spectral energy in tremor band
            - smooth_score  : exponentially-smoothed severity score (0-100)
        """
        self.ax_buf.append(ax)
        self.ay_buf.append(ay)
        self.az_buf.append(az)
        self.timestamps.append(timestamp)

        # Maintain sliding window
        if len(self.ax_buf) > self.window_size:
            self.ax_buf.pop(0)
            self.ay_buf.pop(0)
            self.az_buf.pop(0)
            self.timestamps.pop(0)

        # Need at least half a window for meaningful FFT
        if len(self.ax_buf) >= self.window_size // 2:
            return self._analyze()

        return {
            "frequency_hz": 0.0,
            "amplitude_g": 0.0,
            "severity": "Collecting Data...",
            "energy_ratio": 0.0,
            "smooth_score": 0.0,
        }

    # ── Core Analysis ────────────────────────────────────────────────────
    def _analyze(self) -> dict:
        """
        Full signal-processing pipeline:
            DC removal → magnitude → bandpass filter → Hanning window →
            FFT → peak detection → energy ratio → severity classification.
        """
        a_x = np.array(self.ax_buf, dtype=np.float64)
        a_y = np.array(self.ay_buf, dtype=np.float64)
        a_z = np.array(self.az_buf, dtype=np.float64)

        # Step 1 — Remove DC offset (gravity component)
        a_x -= np.mean(a_x)
        a_y -= np.mean(a_y)
        a_z -= np.mean(a_z)

        # Step 2 — Compute acceleration magnitude
        magnitude = np.sqrt(a_x**2 + a_y**2 + a_z**2)

        # Step 3 — Apply Butterworth bandpass filter (3–12 Hz)
        try:
            magnitude_filtered = filtfilt(self._bp_b, self._bp_a, magnitude)
        except ValueError:
            magnitude_filtered = magnitude  # fallback if signal too short

        # Step 4 — Apply Hanning window to reduce spectral leakage
        n = len(magnitude_filtered)
        window = np.hanning(n)
        windowed_signal = magnitude_filtered * window

        # Step 5 — FFT
        yf = rfft(windowed_signal)
        xf = rfftfreq(n, 1.0 / self.sampling_rate)

        # Ignore DC bin
        yf_abs = np.abs(yf)[1:]
        xf_clean = xf[1:]

        if len(yf_abs) == 0:
            return self._make_result(0.0, 0.0, "Low", 0.0)

        # Step 6 — Isolate tremor band
        band_mask = (xf_clean >= PARKINSONS_BAND[0]) & (xf_clean <= PARKINSONS_BAND[1])
        band_power = yf_abs[band_mask]
        band_freqs = xf_clean[band_mask]

        # Step 7 — Dominant frequency in tremor band
        if len(band_power) > 0 and np.sum(band_power) > 1e-6:
            peak_idx = np.argmax(band_power)
            dominant_freq = float(band_freqs[peak_idx])
        else:
            dominant_freq = 0.0

        # Step 8 — Spectral energy ratio (tremor band / total)
        total_energy = np.sum(yf_abs**2)
        band_energy = np.sum(band_power**2) if len(band_power) > 0 else 0.0
        energy_ratio = float(band_energy / total_energy) if total_energy > 1e-9 else 0.0

        # Step 9 — RMS amplitude of the filtered signal
        rms_amplitude = float(np.sqrt(np.mean(magnitude_filtered**2)))

        # Step 10 — Severity classification
        severity = self._classify_severity(dominant_freq, rms_amplitude, energy_ratio)

        return self._make_result(dominant_freq, rms_amplitude, severity, energy_ratio)

    # ── Severity Classifier ──────────────────────────────────────────────
    def _classify_severity(self, freq: float, rms: float, energy_ratio: float) -> str:
        """
        Multi-feature severity classification.

        Uses dominant frequency, RMS amplitude, and spectral energy ratio
        to distinguish clinically significant tremor from noise.

        Classification Logic:
            HIGH     — Strong amplitude AND high energy concentration in PD band
            MODERATE — Either notable amplitude OR moderate energy ratio
            LOW      — Below both thresholds (normal physiological motion)
        """
        amp_high, er_high = SEVERITY_THRESHOLDS["High"]
        amp_mod, er_mod = SEVERITY_THRESHOLDS["Moderate"]

        # Must be in clinical tremor range to be High
        if 3.0 <= freq <= 8.0 and rms >= amp_high and energy_ratio >= er_high:
            return "High"

        if rms >= amp_mod and energy_ratio >= er_mod:
            return "Moderate"

        # Elevated motion outside tremor band
        if rms >= 0.5:
            return "Moderate"

        return "Low"

    # ── Helpers ──────────────────────────────────────────────────────────
    def _make_result(self, freq: float, rms: float, severity: str, energy_ratio: float) -> dict:
        """Build the output dict and update the smoothed score."""
        # Map severity to a 0-100 score for smoothing
        score_map = {"Low": 10.0, "Moderate": 50.0, "High": 90.0, "Collecting Data...": 0.0}
        raw_score = score_map.get(severity, 0.0)

        self._smooth_score = (
            SMOOTHING_ALPHA * raw_score + (1 - SMOOTHING_ALPHA) * self._smooth_score
        )
        self._prev_severity = severity

        return {
            "frequency_hz": round(freq, 2),
            "amplitude_g": round(rms, 4),
            "severity": severity,
            "energy_ratio": round(energy_ratio, 4),
            "smooth_score": round(self._smooth_score, 2),
        }
