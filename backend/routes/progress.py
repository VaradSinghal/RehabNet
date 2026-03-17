from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from database import get_db
from models import schemas, db_models

router = APIRouter(prefix="/progress", tags=["Progress Analytics"])

@router.get("/{user_id}", response_model=schemas.ProgressResponse)
def get_user_progress(user_id: int, db: Session = Depends(get_db)):
    user = db.query(db_models.User).filter(db_models.User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    sessions = db.query(db_models.SessionLog).filter(db_models.SessionLog.user_id == user_id).all()
    
    total_sess = len(sessions)
    avg_acc = sum([s.avg_accuracy for s in sessions]) / total_sess if total_sess > 0 else 0

    # Format the historical tremor scores attached to these sessions
    history = []
    # For MVP we simply return the average tremor score per session as the trend line
    for s in sessions:
        if s.end_time:
             history.append({
                 "date": s.end_time.strftime("%Y-%m-%d %H:%M:%S"),
                 "avg_tremor_score": s.avg_tremor_score
             })

    return {
        "user_id": user_id,
        "total_sessions": total_sess,
        "average_accuracy": avg_acc,
        "historical_tremor_trend": history
    }
