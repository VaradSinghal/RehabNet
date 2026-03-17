from sqlalchemy.orm import Session
from models import schemas, db_models
from ai.tremor_detector import TremorDetector

# In-memory detector per user (MVP caching)
# In production, use Redis or passing states 
# to avoid managing long-lived objects in memory.
_active_detectors = {}

def get_tremor_detector(user_id: int) -> TremorDetector:
    if user_id not in _active_detectors:
        _active_detectors[user_id] = TremorDetector()
    return _active_detectors[user_id]

def process_sensor_data(db: Session, data: schemas.SensorData) -> schemas.SensorResponse:
    detector = get_tremor_detector(data.user_id)
    
    # Process FFT
    result = detector.process_sample(data.ax, data.ay, data.az, data.timestamp)
    
    # If the window triggered a full analysis, and a session is active, log it.
    if result["severity"] != "Collecting Data...":
        # Broadcast via WebSocket (Async/non-blocking)
        import asyncio
        from services.websocket_manager import manager
        
        payload = {
            "type": "tremor_update",
            "data": {
                "user_id": data.user_id,
                "frequency_hz": result["frequency_hz"],
                "severity": result["severity"],
                "amplitude": result["amplitude_g"]
            }
        }
        # In FastAPI, you should typically use BackgroundTasks for this, 
        # but for real-time we can use create_task if we are careful.
        asyncio.create_task(manager.broadcast(payload))

        if data.session_id:
            db_score = db_models.TremorScore(
                session_id=data.session_id,
                frequency_hz=result["frequency_hz"],
                amplitude_g=result["amplitude_g"],
                severity=result["severity"]
            )
            db.add(db_score)
            db.commit()

    return schemas.SensorResponse(
        status="success",
        frequency_hz=result["frequency_hz"],
        severity=result["severity"],
        amplitude=result["amplitude_g"]
    )
