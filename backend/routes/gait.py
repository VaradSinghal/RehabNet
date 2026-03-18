from fastapi import APIRouter
from models import schemas
from ai.gait_analyzer import GaitAnalyzer
from pydantic import BaseModel
from typing import List
import logging

logger = logging.getLogger("rehabnet")

router = APIRouter(prefix="/gait-data", tags=["Gait Analysis"])

# In-memory analyzer per user (MVP)
_analyzers = {}

def _get_analyzer(user_id: int) -> GaitAnalyzer:
    if user_id not in _analyzers:
        _analyzers[user_id] = GaitAnalyzer()
    return _analyzers[user_id]


class GaitInput(BaseModel):
    user_id: int
    ankle_y_trajectory: List[float]
    time_delta_ms: int = 0


class GaitResponse(BaseModel):
    status: str
    feedback: str
    cadence: float
    stride_variability: float
    freeze_index: float
    step_count: int


@router.post("/", response_model=GaitResponse)
def analyze_gait_data(data: GaitInput):
    """
    Accepts ankle Y-position trajectory data from the Flutter app.
    Runs gait analysis including step detection and Freeze-of-Gait detection.
    """
    analyzer = _get_analyzer(data.user_id)
    result = analyzer.analyze_gait(data.ankle_y_trajectory, data.time_delta_ms)

    if result["status"] != "Needs Data":
        logger.info(
            f"[Gait] user={data.user_id} status={result['status']} "
            f"cadence={result['cadence']} FI={result['freeze_index']}"
        )

    return GaitResponse(**result)
