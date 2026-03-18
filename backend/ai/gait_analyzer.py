"""
Gait Analyzer — Walking Pattern & Freezing-of-Gait Detection
=============================================================

Analyses lower-limb accelerometer or pose data to detect gait
abnormalities common in Parkinson's Disease, particularly
Freezing of Gait (FOG).

Analysis Pipeline:
    1. Buffer incoming ankle Y-trajectory samples.
    2. Detect individual steps using zero-crossing of the
       de-trended vertical displacement signal.
    3. Compute gait metrics:
        a. Cadence (steps / min)
        b. Stride time mean & variability (CV%)
        c. Step height regularity
    4. Compute Freeze Index (FI):
        - Ratio of spectral power in the freeze band (0.5–3 Hz)
          to the locomotor band (3–8 Hz).
        - FI > 1.0 indicates freezing episode.
    5. Classify overall gait quality.

Clinical Basis:
    - Freezing of Gait (FOG) is a disabling symptom in PD where patients
      suddenly feel their feet are "glued" to the floor.
    - FOG detection via accelerometry: Moore ST et al. "Autonomous
      identification of freezing of gait in Parkinson's disease from
      lower-body segmental accelerometry." J NeuroEng Rehabil. 2013.
    - Stride variability > 10% CV is clinically significant.
    - Normal cadence for elderly: 100–120 steps/min.
"""

import numpy as np
from scipy.fft import rfft, rfftfreq
from typing import List, Optional


# ── Constants ────────────────────────────────────────────────────────────────
FREEZE_BAND   = (0.5, 3.0)   # Hz — characteristic of FOG
LOCOMOTOR_BAND = (3.0, 8.0)   # Hz — normal walking frequency
FREEZE_INDEX_THRESHOLD = 1.5   # FI > this → freezing detected
MIN_SAMPLES = 20               # Minimum data points for analysis
NORMAL_CADENCE_RANGE = (80, 140)  # steps/min for elderly


class GaitAnalyzer:
    """
    Stateful gait analyzer.  Accumulates ankle trajectory data and produces
    increasingly accurate analysis as more data arrives.

    Can be used with:
        - ML Kit lower-body pose landmarks (ankle Y positions over time)
        - IMU accelerometer data attached to the ankle/leg

    Parameters
    ----------
    sampling_rate_hz : float
        Estimated sampling rate of incoming data.
    """

    def __init__(self, sampling_rate_hz: float = 30.0):
        self.sampling_rate = sampling_rate_hz
        self.trajectory: list[float] = []
        self._max_buffer = 512  # ~17 seconds of data at 30 Hz

    # ── Public API ───────────────────────────────────────────────────────
    def add_sample(self, ankle_y: float):
        """Add a single ankle Y-position sample to the buffer."""
        self.trajectory.append(ankle_y)
        if len(self.trajectory) > self._max_buffer:
            self.trajectory.pop(0)

    def analyze_gait(self, ankle_y_trajectory: Optional[List[float]] = None,
                     time_delta_ms: int = 0) -> dict:
        """
        Perform full gait analysis.

        Parameters
        ----------
        ankle_y_trajectory : list[float], optional
            If provided, overrides the internal buffer (backward-compatible API).
        time_delta_ms : int
            Total time span of the data in milliseconds (for cadence fallback).

        Returns
        -------
        dict with keys:
            - status    : 'Normal' | 'Unstable' | 'Freezing detected' | 'Needs Data'
            - feedback  : Coaching string
            - cadence   : Steps per minute (float)
            - stride_variability : Coefficient of variation (%)
            - freeze_index : Ratio of freeze/locomotor spectral power
            - step_count : Number of detected steps
        """
        data = ankle_y_trajectory if ankle_y_trajectory is not None else self.trajectory

        if len(data) < MIN_SAMPLES:
            return {
                "status": "Needs Data",
                "feedback": "Start walking — data is being collected.",
                "cadence": 0.0,
                "stride_variability": 0.0,
                "freeze_index": 0.0,
                "step_count": 0,
            }

        signal = np.array(data, dtype=np.float64)

        # Step 1 — De-trend (remove slow drift / baseline)
        signal_detrended = signal - np.convolve(signal, np.ones(15) / 15, mode='same')

        # Step 2 — Detect steps via zero-crossings (rising edge)
        steps = self._detect_steps(signal_detrended)

        # Step 3 — Compute stride metrics
        cadence, stride_cv = self._compute_stride_metrics(steps)

        # Step 4 — Compute Freeze Index via spectral analysis
        freeze_index = self._compute_freeze_index(signal_detrended)

        # Step 5 — Classify gait quality
        status, feedback = self._classify_gait(cadence, stride_cv, freeze_index, len(steps))

        return {
            "status": status,
            "feedback": feedback,
            "cadence": round(cadence, 1),
            "stride_variability": round(stride_cv, 1),
            "freeze_index": round(freeze_index, 3),
            "step_count": len(steps),
        }

    def reset(self):
        """Clear the internal buffer."""
        self.trajectory.clear()

    # ── Step Detection ───────────────────────────────────────────────────
    def _detect_steps(self, signal: np.ndarray) -> list[int]:
        """
        Detect steps using zero-crossings of the de-trended signal.

        A step is registered at each positive-going zero-crossing where
        the signal amplitude exceeds a minimum threshold (to ignore noise).

        Returns list of sample indices where steps were detected.
        """
        threshold = np.std(signal) * 0.3  # Adaptive noise threshold
        steps = []

        for i in range(1, len(signal)):
            # Positive-going zero crossing with sufficient amplitude
            if signal[i - 1] <= 0 < signal[i] and abs(signal[i]) > threshold:
                # Prevent double-counting (min 0.25s between steps)
                min_gap = int(self.sampling_rate * 0.25)
                if not steps or (i - steps[-1]) > min_gap:
                    steps.append(i)

        return steps

    # ── Stride Metrics ───────────────────────────────────────────────────
    def _compute_stride_metrics(self, steps: list[int]) -> tuple[float, float]:
        """
        Compute cadence and stride variability from step indices.

        Cadence = steps per minute.
        Stride variability = coefficient of variation of inter-step intervals.
        """
        if len(steps) < 3:
            return 0.0, 0.0

        intervals = np.diff(steps) / self.sampling_rate  # seconds between steps
        mean_interval = np.mean(intervals)

        if mean_interval < 1e-6:
            return 0.0, 0.0

        cadence = 60.0 / mean_interval  # steps per minute
        cv = float(np.std(intervals) / mean_interval * 100)  # percentage

        return float(cadence), cv

    # ── Freeze Index ─────────────────────────────────────────────────────
    def _compute_freeze_index(self, signal: np.ndarray) -> float:
        """
        Compute the Freeze Index (FI) using spectral power ratio.

        FI = Power(freeze_band) / Power(locomotor_band)

        A high FI (> 1.5) indicates the presence of Freezing of Gait:
        the patient's movement is dominated by low-frequency shuffling
        rather than normal stepping rhythm.
        """
        n = len(signal)
        if n < 32:
            return 0.0

        # Apply window
        windowed = signal * np.hanning(n)
        yf = rfft(windowed)
        xf = rfftfreq(n, 1.0 / self.sampling_rate)
        power = np.abs(yf) ** 2

        # Freeze band power (0.5 – 3 Hz)
        freeze_mask = (xf >= FREEZE_BAND[0]) & (xf <= FREEZE_BAND[1])
        freeze_power = np.sum(power[freeze_mask])

        # Locomotor band power (3 – 8 Hz)
        loco_mask = (xf >= LOCOMOTOR_BAND[0]) & (xf <= LOCOMOTOR_BAND[1])
        loco_power = np.sum(power[loco_mask])

        if loco_power < 1e-9:
            return float(freeze_power) if freeze_power > 1e-6 else 0.0

        return float(freeze_power / loco_power)

    # ── Classification ───────────────────────────────────────────────────
    def _classify_gait(self, cadence: float, stride_cv: float,
                       freeze_index: float, step_count: int) -> tuple[str, str]:
        """
        Multi-feature gait classification.

        Priority order:
            1. Freezing of Gait (highest clinical concern)
            2. High stride variability (fall risk)
            3. Abnormal cadence
            4. Normal gait
        """
        if step_count < 3:
            return "Needs Data", "Keep walking — more steps needed for analysis."

        # Freezing detection (highest priority)
        if freeze_index > FREEZE_INDEX_THRESHOLD:
            return (
                "Freezing detected",
                "Freezing episode detected. Try to take a deliberate, large step. "
                "Focus on a point ahead and imagine stepping over a line on the floor.",
            )

        # Stride variability
        if stride_cv > 15.0:
            return (
                "Unstable",
                "Your steps are uneven. Try to maintain a steady rhythm. "
                "Counting '1-2-1-2' in your head can help regulate your pace.",
            )

        # Cadence analysis
        if cadence < NORMAL_CADENCE_RANGE[0]:
            return (
                "Unstable",
                f"Your pace is slow ({cadence:.0f} steps/min). "
                "Try to pick up your pace slightly while staying comfortable.",
            )
        if cadence > NORMAL_CADENCE_RANGE[1]:
            return (
                "Unstable",
                f"Your pace is very fast ({cadence:.0f} steps/min). "
                "Slow down and focus on making each step deliberate and controlled.",
            )

        return (
            "Normal",
            f"Good rhythm! Cadence: {cadence:.0f} steps/min, "
            f"stride variability: {stride_cv:.1f}%. Keep it up!",
        )
