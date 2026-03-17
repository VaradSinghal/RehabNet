from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from database import get_db
from models import schemas, db_models

router = APIRouter(prefix="/session", tags=["Session Tracking"])

@router.post("/start", response_model=schemas.SessionResponse)
def start_session(req: schemas.SessionCreate, db: Session = Depends(get_db)):
    """Creates a new rehabilitation session in the database."""
    user = db.query(db_models.User).filter(db_models.User.id == req.user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    new_session = db_models.SessionLog(user_id=user.id)
    db.add(new_session)
    db.commit()
    db.refresh(new_session)

    return {"status": "success", "message": "Session started", "session_id": new_session.id}


@router.post("/end", response_model=schemas.SessionResponse)
def end_session(req: schemas.SessionEnd, db: Session = Depends(get_db)):
    """Updates the session with final average scores (Tremor, Accuracy) and marks an end time."""
    db_session = db.query(db_models.SessionLog).filter(db_models.SessionLog.id == req.session_id).first()
    if not db_session:
        raise HTTPException(status_code=404, detail="Session not found")

    import datetime
    db_session.end_time = datetime.datetime.utcnow()
    db_session.exercise_count = req.exercise_count
    db_session.avg_accuracy = req.avg_accuracy
    db_session.avg_tremor_score = req.avg_tremor_score

    db.commit()

    return {"status": "success", "message": "Session finalized", "session_id": db_session.id}
