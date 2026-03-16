"""
Session Manager
Tracks all per-session metrics and exposes a JSON snapshot.
"""

import time
from threading import Lock


class SessionManager:
    def __init__(self):
        self._lock = Lock()
        self._active = False
        self._start_time: float = 0.0
        self._reps: int = 0
        self._accuracy_history: list[float] = []
        self._tremor_history: list[dict] = []   # {time, score, label}

    # ------------------------------------------------------------------
    def start_session(self):
        with self._lock:
            self._active = True
            self._start_time = time.time()
            self._reps = 0
            self._accuracy_history = []
            self._tremor_history = []

    def stop_session(self):
        with self._lock:
            self._active = False

    @property
    def is_active(self) -> bool:
        return self._active

    # ------------------------------------------------------------------
    def record_rep(self, accuracy_pct: float):
        with self._lock:
            if self._active:
                self._reps += 1
                self._accuracy_history.append(accuracy_pct)

    def record_tremor(self, score: float, label: str):
        with self._lock:
            if self._active:
                self._tremor_history.append({
                    "t": round(time.time() - self._start_time, 1),
                    "score": score,
                    "label": label,
                })
                # Keep last 600 entries (~60 s at 10 Hz)
                if len(self._tremor_history) > 600:
                    self._tremor_history = self._tremor_history[-600:]

    # ------------------------------------------------------------------
    def get_metrics(self) -> dict:
        with self._lock:
            elapsed = time.time() - self._start_time if self._active else 0.0
            avg_accuracy = (
                round(sum(self._accuracy_history) / len(self._accuracy_history), 1)
                if self._accuracy_history else 0.0
            )
            last_tremor = self._tremor_history[-1] if self._tremor_history else {}
            return {
                "session_active":  self._active,
                "duration_s":      round(elapsed, 1),
                "reps":            self._reps,
                "avg_accuracy_pct": avg_accuracy,
                "tremor_score":    last_tremor.get("score", 0.0),
                "tremor_label":    last_tremor.get("label", "Low"),
                "tremor_history":  list(self._tremor_history),
            }
