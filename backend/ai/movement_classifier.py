import numpy as np

class MovementClassifier:
    """
    Evaluates ML Kit joint landmarks.
    Currently uses Rule-based heuristics (MVP).
    Designed to be easily swappable with a Random Forest model.
    """
    def __init__(self):
        # In the future: self.model = joblib.load('random_forest.pkl')
        pass

    def classify_movement(self, landmarks: list, exercise: str) -> dict:
        """
        Takes a list of Pydantic landmarks.
        Returns classification, feedback string, and accuracy percentage.
        """
        if not landmarks:
            return {
                "classification": "No Skeleton",
                "feedback": "Step completely into frame",
                "accuracy_pct": 0.0
            }

        # Convert to dictionary for easy lookup
        lms = {lm.type: lm for lm in landmarks}

        if exercise == "arm_raise":
            return self._classify_arm_raise(lms)
        else:
            return {
                "classification": "Unknown",
                "feedback": f"Exercise {exercise} not implemented",
                "accuracy_pct": 0.0
            }

    def _classify_arm_raise(self, lms: dict) -> dict:
        """Rule-based logic for testing arm raises."""
        try:
            # Need wrist and shoulder to check raise
            wrist_l = lms.get("leftWrist")
            wrist_r = lms.get("rightWrist")
            shoulder_l = lms.get("leftShoulder")
            shoulder_r = lms.get("rightShoulder")

            if wrist_r is None or shoulder_r is None:
                return {"classification": "Incorrect", "feedback": "Right arm not visible", "accuracy_pct": 0.0}

            # Double check likelihood even if not None
            if getattr(wrist_r, "likelihood", 0) < 0.5 or getattr(shoulder_r, "likelihood", 0) < 0.5:
                return {"classification": "Incorrect", "feedback": "Right arm tracking low confidence", "accuracy_pct": 0.0}

            # In ML Kit, y goes from 0 (top) to 1 (bottom).
            # Arm is raised perfectly if wrist_y is significantly LESS than shoulder_y
            height_diff = float(getattr(shoulder_r, 'y', 0)) - float(getattr(wrist_r, 'y', 0))
            
            # Simple heuristic
            if height_diff > 0.3: # Fully raised above shoulder
                return {"classification": "Correct", "feedback": "Excellent extension!", "accuracy_pct": 95.0}
            elif height_diff > 0.0: # Reached shoulder level
                return {"classification": "Needs Improvement", "feedback": "Raise your hand higher", "accuracy_pct": 60.0}
            else: # Wrist is below shoulder
                return {"classification": "Incorrect", "feedback": "Keep arms straight and raise them up", "accuracy_pct": 20.0}

        except Exception as e:
            return {"classification": "Error", "feedback": "Could not analyze pose", "accuracy_pct": 0.0}

    def _calculate_angle(self, a, b, c) -> float:
        """Utility for more complex angle-based rules or RF feature extraction."""
        a = np.array([a.x, a.y])
        b = np.array([b.x, b.y])
        c = np.array([c.x, c.y])

        ba = a - b
        bc = c - b

        cosine_angle = np.dot(ba, bc) / (np.linalg.norm(ba) * np.linalg.norm(bc))
        angle = np.arccos(cosine_angle)

        return np.degrees(angle)
