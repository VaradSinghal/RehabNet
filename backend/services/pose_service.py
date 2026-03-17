import json
from sqlalchemy.orm import Session
from models import schemas
from ai.movement_classifier import MovementClassifier

classifier = MovementClassifier()

def process_pose_data(db: Session, data: schemas.PoseData) -> schemas.PoseResponse:
    # MVP: Log the request locally for debugging
    # print(f"Processing pose for user {data.user_id}, exercise: {data.exercise}")
    
    # Send landmarks to AI Classifier
    result = classifier.classify_movement(data.landmarks, data.exercise)
    
    # If using Session ID, we could increment rep counters in DB here if classification is "Correct".
    # That falls under the SessionService tracking.

    return schemas.PoseResponse(
        status="success",
        classification=result["classification"],
        feedback=result["feedback"],
        accuracy_pct=result["accuracy_pct"]
    )
