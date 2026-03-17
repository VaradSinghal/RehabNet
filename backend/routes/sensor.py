from fastapi import APIRouter, Depends, BackgroundTasks
from sqlalchemy.orm import Session
from database import get_db
from models import schemas
import services.sensor_service as sensor_service

router = APIRouter(prefix="/sensor-data", tags=["Sensor Data"])

@router.post("/", response_model=schemas.SensorResponse)
def receive_sensor_data(data: schemas.SensorData, background_tasks: BackgroundTasks, db: Session = Depends(get_db)):
    """
    ESP32 Hardware POST endpoint.
    Expects timestamp, ax, ay, az. Processes via FFT for Tremor detection.
    """
    return sensor_service.process_sensor_data(db, data, background_tasks)
