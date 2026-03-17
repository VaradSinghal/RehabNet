from fastapi import FastAPI, Depends, WebSocket, WebSocketDisconnect
from typing import List
from fastapi.middleware.cors import CORSMiddleware
from database import engine, Base, SessionLocal
from routes import pose, sensor, session, progress
from models import db_models
from services.websocket_manager import manager

import logging

# Configure basic logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("rehabnet")

# Initialize Database tables
Base.metadata.create_all(bind=engine)

app = FastAPI(
    title="RehabNet API",
    description="Backend for Parkinson's Rehabilitation Platform",
    version="1.0.0"
)

# CORS Setup for Flutter/Web clients
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include API Routers
app.include_router(pose.router)
app.include_router(sensor.router)
app.include_router(session.router)
app.include_router(progress.router)

@app.websocket("/ws/live")
async def websocket_endpoint(websocket: WebSocket):
    await manager.connect(websocket)
    try:
        while True:
            # Keep alive and wait for client to close
            await websocket.receive_text()
    except WebSocketDisconnect:
        manager.disconnect(websocket)

@app.on_event("startup")
def startup_event():
    logger.info("RehabNet Backend Starting Up...")
    logger.info("Initializing Local SQLite Database...")
    
    # Create a test user for MVP if it doesn't exist
    db = SessionLocal()
    user = db.query(db_models.User).filter(db_models.User.id == 1).first()
    if not user:
        test_user = db_models.User(username="test_patient")
        db.add(test_user)
        db.commit()
    db.close()


@app.get("/")
def read_root():
    return {
        "status": "online",
        "service": "RehabNet FastAPI",
        "docs": "Visit /docs for Interactive API Documentation"
    }

if __name__ == "__main__":
    import uvicorn
    # Start the Uvicorn ASGI server
    uvicorn.run("main:app", host="0.0.0.0", port=5000, reload=True)
