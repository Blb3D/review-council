"""Review run data models."""

from __future__ import annotations

from datetime import datetime
from enum import Enum
from typing import Optional

from pydantic import BaseModel

from .finding import FindingSummary


class Verdict(str, Enum):
    SHIP = "SHIP"
    CONDITIONAL = "CONDITIONAL"
    HOLD = "HOLD"


class ReviewRun(BaseModel):
    id: str
    timestamp: datetime
    project: str = ""
    project_path: str = ""
    duration_seconds: float = 0
    dry_run: bool = False
    base_branch: Optional[str] = None
    standard: Optional[str] = None
    provider: str = "unknown"
    agents_requested: list[str] = []


class RunArchive(BaseModel):
    version: str = "1.0.0"
    run: ReviewRun
    verdict: Verdict
    exit_code: int = 0
    summary: FindingSummary = FindingSummary()
    agents: dict = {}
