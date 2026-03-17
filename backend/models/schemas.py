from pydantic import BaseModel
from typing import List, Optional
from datetime import datetime

# --- Sensor Data Input ---
class SensorData(BaseModel):
    user_id: int
    session_id: Optional[int] = None
    ax: float
    ay: float
    az: float
    timestamp: int

# --- Sensor Data Output ---
class SensorResponse(BaseModel):
    status: str
    frequency_hz: float
    severity: str
    amplitude: float

# --- Pose Data Input ---
class Landmark(BaseModel):
    x: float
    y: float
    z: float
    likelihood: float
    type: str

class PoseData(BaseModel):
    user_id: int
    session_id: Optional[int] = None
    landmarks: List[Landmark]
    exercise: str = "arm_raise"

# --- Pose Data Output ---
class PoseResponse(BaseModel):
    status: str
    classification: str # "Correct", "Incorrect", "Needs Improvement"
    feedback: str
    accuracy_pct: float

# --- Session Data ---
class SessionCreate(BaseModel):
    user_id: int

class SessionEnd(BaseModel):
    session_id: int
    exercise_count: int
    avg_accuracy: float
    avg_tremor_score: float

class SessionResponse(BaseModel):
    status: str
    message: str
    session_id: int

# --- Progress Output ---
class ProgressResponse(BaseModel):
    user_id: int
    total_sessions: int
    average_accuracy: float
    historical_tremor_trend: List[dict] # [ { date: string, severity: string } ]
