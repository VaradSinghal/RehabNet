from typing import List

class GaitAnalyzer:
    """
    Optional module to detect walking irregularities (Freezing of Gait).
    Can utilize either lower-body ML Kit pose data or IMU data strapped to leg.
    """
    def __init__(self):
        self.step_history = []

    def analyze_gait(self, ankle_y_trajectory: List[float], time_delta_ms: int) -> dict:
        """
        Placeholder logic for analyzing stepping height and cadence.
        Returns Normal, Unstable, or Freezing.
        """
        if len(ankle_y_trajectory) < 10:
            return {"status": "Needs Data", "feedback": "Start walking", "cadence": 0}

        # Calculate standard deviation of height (variance in stepping)
        import numpy as np
        std_dev = np.std(ankle_y_trajectory)

        if std_dev < 0.02:
            return {"status": "Freezing detected", "feedback": "Try to take a larger step", "cadence": 0}
        
        # Extremely basic mockup of cadence
        estimated_cadence = len(ankle_y_trajectory) / (time_delta_ms / 1000.0) * 60.0

        if estimated_cadence < 40 or std_dev > 0.2:
            return {"status": "Unstable", "feedback": "Pace yourself, step evenly", "cadence": estimated_cadence}

        return {"status": "Normal", "feedback": "Good rhythm", "cadence": estimated_cadence}
