"""
Movement Classifier — Pose-Based Exercise Evaluation Engine
============================================================

Evaluates body pose landmarks from Google ML Kit (sent by the Flutter
frontend) and classifies movement quality for rehabilitation exercises.

Supported Exercises:
    1. **arm_raise**         — Bilateral overhead arm raise
    2. **shoulder_flexion**  — Forward arm raise (sagittal plane)
    3. **elbow_curl**        — Bicep curl with elbow angle tracking
    4. **lateral_raise**     — Side arm abduction

Evaluation Approach:
    - Extract relevant joint coordinates from ML Kit landmarks.
    - Compute inter-joint angles using the law of cosines.
    - Compare measured angles to exercise-specific ideal ranges.
    - Generate continuous accuracy scores (0-100%) and natural-language feedback.
    - Optionally compare left vs right side for symmetry analysis.

Clinical Basis:
    - Rehabilitation exercises are designed to improve range of motion (ROM)
      and motor control in Parkinson's patients.
    - Accuracy thresholds are calibrated to encourage gradual improvement
      while remaining achievable for elderly users.
    - Reference: Morris ME. "Movement disorders in people with Parkinson disease."
      Phys Ther. 2000;80(6):578-597.
"""

import numpy as np
from typing import Optional


class MovementClassifier:
    """
    Stateless exercise classifier.  Each call to ``classify_movement()``
    evaluates a single frame of pose landmarks against the specified exercise.

    Designed for easy extensibility — adding a new exercise requires only:
        1. A new ``_classify_<exercise_name>`` method.
        2. Registration in the ``_EXERCISE_MAP`` dispatch table.
    """

    def __init__(self):
        # Dispatch table — maps exercise name to handler method
        self._EXERCISE_MAP = {
            "arm_raise":        self._classify_arm_raise,
            "shoulder_flexion": self._classify_shoulder_flexion,
            "elbow_curl":       self._classify_elbow_curl,
            "lateral_raise":    self._classify_lateral_raise,
        }

    # ── Public API ───────────────────────────────────────────────────────
    def classify_movement(self, landmarks: list, exercise: str) -> dict:
        """
        Evaluate a set of pose landmarks against the specified exercise.

        Parameters
        ----------
        landmarks : list
            List of Pydantic Landmark objects (x, y, z, likelihood, type).
        exercise : str
            Exercise identifier (must match a key in ``_EXERCISE_MAP``).

        Returns
        -------
        dict with keys:
            - classification : 'Correct' | 'Needs Improvement' | 'Incorrect' | 'No Skeleton'
            - feedback       : Human-readable coaching string
            - accuracy_pct   : 0.0 – 100.0
            - symmetry       : Optional left/right comparison dict
        """
        if not landmarks:
            return {
                "classification": "No Skeleton",
                "feedback": "Step completely into frame so the camera can see you.",
                "accuracy_pct": 0.0,
                "symmetry": None,
            }

        # Build lookup dictionary  { "leftWrist": Landmark, ... }
        lms = {lm.type: lm for lm in landmarks}

        handler = self._EXERCISE_MAP.get(exercise)
        if handler is None:
            return {
                "classification": "Unknown",
                "feedback": f"Exercise '{exercise}' is not supported yet.",
                "accuracy_pct": 0.0,
                "symmetry": None,
            }

        return handler(lms)

    # ── Exercise: Arm Raise ──────────────────────────────────────────────
    def _classify_arm_raise(self, lms: dict) -> dict:
        """
        Bilateral overhead arm raise.

        Ideal: Both wrists are raised well above the corresponding shoulder.
        Measured via vertical displacement (in normalised ML Kit coords,
        lower y = higher position on screen).

        Scoring:
            - Computes height difference per side: shoulder_y − wrist_y
            - Maps height_diff to a 0–100 accuracy scale
            - Averages left and right sides
        """
        result_r = self._eval_arm_height(lms, "right")
        result_l = self._eval_arm_height(lms, "left")

        if result_r is None and result_l is None:
            return self._error("Arms not visible — face the camera.")

        scores = [r["accuracy"] for r in [result_r, result_l] if r is not None]
        avg_accuracy = sum(scores) / len(scores)

        symmetry = None
        if result_r is not None and result_l is not None:
            symmetry = {
                "left_accuracy": result_l["accuracy"],
                "right_accuracy": result_r["accuracy"],
                "imbalance": abs(result_r["accuracy"] - result_l["accuracy"]),
            }

        classification, feedback = self._score_to_feedback(
            avg_accuracy,
            good_msg="Excellent arm raise! Great extension.",
            mid_msg="Raise your hands higher — try to reach above your head.",
            low_msg="Keep your arms straight and push them upward.",
        )

        # Add symmetry warning
        if symmetry and symmetry["imbalance"] > 25:
            weaker = "left" if symmetry["left_accuracy"] < symmetry["right_accuracy"] else "right"
            feedback += f" Focus on your {weaker} arm."

        return {
            "classification": classification,
            "feedback": feedback,
            "accuracy_pct": round(avg_accuracy, 1),
            "symmetry": symmetry,
        }

    def _eval_arm_height(self, lms: dict, side: str) -> Optional[dict]:
        """Evaluate a single arm's raising height."""
        wrist = lms.get(f"{side}Wrist")
        shoulder = lms.get(f"{side}Shoulder")

        if wrist is None or shoulder is None:
            return None
        if getattr(wrist, "likelihood", 0) < 0.4 or getattr(shoulder, "likelihood", 0) < 0.4:
            return None

        height_diff = float(getattr(shoulder, 'y', 0)) - float(getattr(wrist, 'y', 0))
        # Map: 0.0 → 0%, 0.35 → 100%
        accuracy = np.clip(height_diff / 0.35 * 100, 0, 100)
        return {"accuracy": float(accuracy)}

    # ── Exercise: Shoulder Flexion (Forward Raise) ───────────────────────
    def _classify_shoulder_flexion(self, lms: dict) -> dict:
        """
        Forward arm raise in the sagittal plane.

        Measures the angle at the shoulder joint between the torso (hip)
        and the arm (wrist).  Ideal ROM: 150–180°.

        Landmarks used: hip → shoulder → wrist
        """
        angle_r = self._joint_angle(lms, "rightHip", "rightShoulder", "rightWrist")
        angle_l = self._joint_angle(lms, "leftHip", "leftShoulder", "leftWrist")

        if angle_r is None and angle_l is None:
            return self._error("Cannot see shoulder and arm — adjust your position.")

        scores = []
        if angle_r is not None:
            scores.append(self._angle_to_score(angle_r, ideal=170, tolerance=40))
        if angle_l is not None:
            scores.append(self._angle_to_score(angle_l, ideal=170, tolerance=40))

        avg = sum(scores) / len(scores)
        symmetry = None
        if angle_r is not None and angle_l is not None:
            symmetry = {
                "left_angle": round(angle_l, 1),
                "right_angle": round(angle_r, 1),
                "imbalance": round(abs(angle_r - angle_l), 1),
            }

        classification, feedback = self._score_to_feedback(
            avg,
            good_msg="Great forward raise! Full range of motion achieved.",
            mid_msg="Raise your arm further forward and up.",
            low_msg="Extend your arm straight in front of you, then up.",
        )

        return {
            "classification": classification,
            "feedback": feedback,
            "accuracy_pct": round(avg, 1),
            "symmetry": symmetry,
        }

    # ── Exercise: Elbow Curl ─────────────────────────────────────────────
    def _classify_elbow_curl(self, lms: dict) -> dict:
        """
        Bicep curl — measures elbow flexion angle.

        Ideal flexion: the angle at the elbow should decrease to ≈ 40°
        during the curl phase.

        Landmarks used: shoulder → elbow → wrist
        """
        angle_r = self._joint_angle(lms, "rightShoulder", "rightElbow", "rightWrist")
        angle_l = self._joint_angle(lms, "leftShoulder", "leftElbow", "leftWrist")

        if angle_r is None and angle_l is None:
            return self._error("Cannot see your elbows — face the camera with arms visible.")

        scores = []
        if angle_r is not None:
            # For curls, smaller angle = better (ideal ~40°)
            scores.append(self._angle_to_score(angle_r, ideal=40, tolerance=30))
        if angle_l is not None:
            scores.append(self._angle_to_score(angle_l, ideal=40, tolerance=30))

        avg = sum(scores) / len(scores)
        symmetry = None
        if angle_r is not None and angle_l is not None:
            symmetry = {
                "left_angle": round(angle_l, 1),
                "right_angle": round(angle_r, 1),
                "imbalance": round(abs(angle_r - angle_l), 1),
            }

        classification, feedback = self._score_to_feedback(
            avg,
            good_msg="Perfect curl! Excellent range of motion.",
            mid_msg="Bend your elbow more — bring your hand towards your shoulder.",
            low_msg="Start by bending your elbow slowly. Keep your upper arm still.",
        )

        return {
            "classification": classification,
            "feedback": feedback,
            "accuracy_pct": round(avg, 1),
            "symmetry": symmetry,
        }

    # ── Exercise: Lateral Raise ──────────────────────────────────────────
    def _classify_lateral_raise(self, lms: dict) -> dict:
        """
        Side arm abduction — raise arms out to the sides.

        Measures the angle between the torso midline and the arm.
        Ideal ROM: arms at shoulder height (≈ 80–90° from torso).

        Landmarks used: hip → shoulder → wrist
        """
        angle_r = self._joint_angle(lms, "rightHip", "rightShoulder", "rightWrist")
        angle_l = self._joint_angle(lms, "leftHip", "leftShoulder", "leftWrist")

        if angle_r is None and angle_l is None:
            return self._error("Cannot see your arms — stand facing the camera.")

        scores = []
        if angle_r is not None:
            scores.append(self._angle_to_score(angle_r, ideal=90, tolerance=30))
        if angle_l is not None:
            scores.append(self._angle_to_score(angle_l, ideal=90, tolerance=30))

        avg = sum(scores) / len(scores)
        symmetry = None
        if angle_r is not None and angle_l is not None:
            symmetry = {
                "left_angle": round(angle_l, 1),
                "right_angle": round(angle_r, 1),
                "imbalance": round(abs(angle_r - angle_l), 1),
            }

        classification, feedback = self._score_to_feedback(
            avg,
            good_msg="Great lateral raise! Arms at shoulder height.",
            mid_msg="Lift your arms higher to the sides, aim for shoulder level.",
            low_msg="Raise your arms outward, away from your body.",
        )

        return {
            "classification": classification,
            "feedback": feedback,
            "accuracy_pct": round(avg, 1),
            "symmetry": symmetry,
        }

    # ── Utilities ────────────────────────────────────────────────────────
    def _joint_angle(self, lms: dict, a_name: str, b_name: str, c_name: str) -> Optional[float]:
        """
        Compute the angle (degrees) at joint `b` formed by points a → b → c.

        Uses the dot-product formula:
            cos(θ) = (ba · bc) / (|ba| × |bc|)

        Returns None if any landmark is missing or low-confidence.
        """
        a = lms.get(a_name)
        b = lms.get(b_name)
        c = lms.get(c_name)

        if a is None or b is None or c is None:
            return None
        if any(getattr(pt, "likelihood", 0) < 0.3 for pt in [a, b, c]):
            return None

        va = np.array([float(getattr(a, 'x', 0)), float(getattr(a, 'y', 0))])
        vb = np.array([float(getattr(b, 'x', 0)), float(getattr(b, 'y', 0))])
        vc = np.array([float(getattr(c, 'x', 0)), float(getattr(c, 'y', 0))])

        ba = va - vb
        bc = vc - vb

        norm_product = np.linalg.norm(ba) * np.linalg.norm(bc)
        if norm_product < 1e-9:
            return None

        cosine = np.clip(np.dot(ba, bc) / norm_product, -1.0, 1.0)
        return float(np.degrees(np.arccos(cosine)))

    @staticmethod
    def _angle_to_score(measured: float, ideal: float, tolerance: float) -> float:
        """
        Map a measured angle to a 0-100 accuracy score.

        Full score at the ideal angle; linearly drops to 0 at ± tolerance.
        """
        error = abs(measured - ideal)
        return float(np.clip((1.0 - error / tolerance) * 100, 0, 100))

    @staticmethod
    def _score_to_feedback(score: float, *, good_msg: str, mid_msg: str, low_msg: str) -> tuple:
        """Map a 0-100 score to (classification, feedback) tuple."""
        if score >= 75:
            return ("Correct", good_msg)
        elif score >= 40:
            return ("Needs Improvement", mid_msg)
        else:
            return ("Incorrect", low_msg)

    @staticmethod
    def _error(msg: str) -> dict:
        return {
            "classification": "Incorrect",
            "feedback": msg,
            "accuracy_pct": 0.0,
            "symmetry": None,
        }
