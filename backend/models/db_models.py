from sqlalchemy import Column, Integer, String, Float, DateTime, ForeignKey
from sqlalchemy.orm import relationship
from datetime import datetime
from database import Base

class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    username = Column(String, unique=True, index=True)
    
    sessions = relationship("SessionLog", back_populates="user")

class SessionLog(Base):
    __tablename__ = "session_logs"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"))
    start_time = Column(DateTime, default=datetime.utcnow)
    end_time = Column(DateTime, nullable=True)
    exercise_count = Column(Integer, default=0)
    avg_accuracy = Column(Float, default=0.0)
    avg_tremor_score = Column(Float, default=0.0)

    user = relationship("User", back_populates="sessions")

class TremorScore(Base):
    __tablename__ = "tremor_scores"
    
    id = Column(Integer, primary_key=True, index=True)
    session_id = Column(Integer, ForeignKey("session_logs.id"))
    timestamp = Column(DateTime, default=datetime.utcnow)
    frequency_hz = Column(Float)
    amplitude_g = Column(Float)
    severity = Column(String) # Low, Medium, High
