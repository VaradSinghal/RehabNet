from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from database import get_db
from models import schemas
import services.pose_service as pose_service

router = APIRouter(prefix="/pose-data", tags=["Pose Data"])

@router.post("/", response_model=schemas.PoseResponse)
def handle_pose_data(data: schemas.PoseData, db: Session = Depends(get_db)):
    """
    Flutter App POST endpoint.
    Expects arrays of 3D landmarks. Uses Rule/RF Classifier to validate exercises.
    Returns real-time audio/visual feedback strings.
    """
    return pose_service.process_pose_data(db, data)
