from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from database import get_db
from models import schemas
import services.sensor_service as sensor_service
from services.websocket_manager import manager

router = APIRouter(prefix="/sensor-data", tags=["Sensor Data"])

@router.post("/", response_model=schemas.SensorResponse)
async def receive_sensor_data(data: schemas.SensorData, db: Session = Depends(get_db)):
    """
    ESP32 Hardware POST endpoint.
    Expects timestamp, ax, ay, az. Processes via FFT for Tremor detection.
    Broadcasts results via WebSocket to connected Flutter clients.
    """
    result = sensor_service.process_sensor_data(db, data)

    # Broadcast via WebSocket in the async context (this is the event loop)
    if result["ws_payload"] is not None:
        await manager.broadcast(result["ws_payload"])

    return result["response"]
