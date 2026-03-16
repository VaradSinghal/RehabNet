"""
Pose Analyzer
Receives body landmark coordinates from the Flutter ML Kit client
and returns joint angles, rep detection, and movement feedback.
"""

import math


class PoseAnalyzer:
    # MediaPipe / ML Kit landmark indices (subset used here)
    LEFT_SHOULDER  = 11
    RIGHT_SHOULDER = 12
    LEFT_ELBOW     = 13
    RIGHT_ELBOW    = 14
    LEFT_WRIST     = 15
    RIGHT_WRIST    = 16
    LEFT_HIP       = 23
    RIGHT_HIP      = 24
    LEFT_KNEE      = 25
    RIGHT_KNEE     = 26

    ARM_RAISE_THRESHOLD = 150   # degrees

    def __init__(self):
        self._prev_above = False   # tracks arm-raise rep transitions

    # ------------------------------------------------------------------
    # Public
    # ------------------------------------------------------------------
    def analyse_frame(self, landmarks: list[dict]) -> dict:
        """
        :param landmarks: list of {index, x, y, z, likelihood}
        :returns: dict with angles, feedback, rep_detected flag
        """
        if not landmarks or len(landmarks) < 27:
            return {"error": "insufficient landmarks"}

        lm = {lm["index"]: lm for lm in landmarks}

        results = {}

        # Left arm angle
        try:
            l_angle = self._angle(
                lm[self.LEFT_SHOULDER],
                lm[self.LEFT_ELBOW],
                lm[self.LEFT_WRIST],
            )
            results["left_arm_angle"] = round(l_angle, 1)
        except KeyError:
            l_angle = None

        # Right arm angle
        try:
            r_angle = self._angle(
                lm[self.RIGHT_SHOULDER],
                lm[self.RIGHT_ELBOW],
                lm[self.RIGHT_WRIST],
            )
            results["right_arm_angle"] = round(r_angle, 1)
        except KeyError:
            r_angle = None

        # Arm-raise exercise analysis (use whichever arm is available)
        angle = l_angle or r_angle
        feedback, accuracy, rep_detected = self._arm_raise_check(angle, lm)

        results.update({
            "feedback":     feedback,
            "accuracy_pct": accuracy,
            "rep_detected": rep_detected,
        })

        return results

    # ------------------------------------------------------------------
    # Exercise-specific logic
    # ------------------------------------------------------------------
    def _arm_raise_check(self, elbow_angle, lm: dict) -> tuple[str, float, bool]:
        """
        Arm raise: patient raises arm until elbow angle > threshold.
        Returns (feedback_text, accuracy_pct, rep_detected).
        """
        rep_detected = False

        if elbow_angle is None:
            return "Position yourself in view of the camera", 0.0, False

        # Accuracy: how close to straight arm (180°)
        accuracy = min(100.0, round((elbow_angle / 180.0) * 100, 1))

        # Rep detection: transition from below → above threshold
        above_threshold = elbow_angle >= self.ARM_RAISE_THRESHOLD
        if above_threshold and not self._prev_above:
            rep_detected = True
        self._prev_above = above_threshold

        # Feedback text
        if elbow_angle < 60:
            feedback = "Raise your arm higher"
        elif elbow_angle < 120:
            feedback = "Keep going — halfway there!"
        elif elbow_angle < self.ARM_RAISE_THRESHOLD:
            feedback = "Almost there — extend fully"
        else:
            feedback = "Movement completed! Great job"

        return feedback, accuracy, rep_detected

    # ------------------------------------------------------------------
    # Geometry
    # ------------------------------------------------------------------
    @staticmethod
    def _angle(a: dict, b: dict, c: dict) -> float:
        """Angle at point B formed by vectors BA and BC (degrees)."""
        ax, ay = a["x"] - b["x"], a["y"] - b["y"]
        cx, cy = c["x"] - b["x"], c["y"] - b["y"]
        dot = ax * cx + ay * cy
        mag_a = math.sqrt(ax ** 2 + ay ** 2)
        mag_c = math.sqrt(cx ** 2 + cy ** 2)
        if mag_a == 0 or mag_c == 0:
            return 0.0
        cos_angle = max(-1.0, min(1.0, dot / (mag_a * mag_c)))
        return math.degrees(math.acos(cos_angle))
