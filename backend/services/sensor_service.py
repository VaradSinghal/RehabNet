from sqlalchemy.orm import Session
from models import schemas, db_models
from ai.tremor_detector import TremorDetector
import logging

logger = logging.getLogger("rehabnet")

# In-memory detector per user (MVP caching)
_active_detectors = {}

def get_tremor_detector(user_id: int) -> TremorDetector:
    if user_id not in _active_detectors:
        _active_detectors[user_id] = TremorDetector()
    return _active_detectors[user_id]


def process_sensor_data(db: Session, data: schemas.SensorData) -> dict:
    """Process incoming sensor data and return both the HTTP response
    and a WebSocket payload. Always sends accel data; adds tremor
    analysis once enough samples are collected."""

    detector = get_tremor_detector(data.user_id)
    result = detector.process_sample(data.ax, data.ay, data.az, data.timestamp)

    # Always broadcast: raw accel + whatever tremor data we have
    ws_payload = {
        "type": "tremor_update",
        "data": {
            "user_id": data.user_id,
            "frequency_hz": result["frequency_hz"],
            "severity": result["severity"],
            "amplitude": result["amplitude_g"],
            "accelerometer_x": data.ax,
            "accelerometer_y": data.ay,
            "accelerometer_z": data.az,
        }
    }

    # Log when tremor analysis kicks in for the first time
    if result["severity"] not in ("Collecting Data...", "Low") or result["frequency_hz"] > 0:
        logger.info(f"[Tremor] freq={result['frequency_hz']}Hz severity={result['severity']} amp={result['amplitude_g']}")

    # Save to DB if a session is active and we have real analysis
    if result["severity"] != "Collecting Data..." and data.session_id:
        db_score = db_models.TremorScore(
            session_id=data.session_id,
            frequency_hz=result["frequency_hz"],
            amplitude_g=result["amplitude_g"],
            severity=result["severity"]
        )
        db.add(db_score)
        db.commit()

    response = schemas.SensorResponse(
        status="success",
        frequency_hz=result["frequency_hz"],
        severity=result["severity"],
        amplitude=result["amplitude_g"]
    )

    return {"response": response, "ws_payload": ws_payload}
