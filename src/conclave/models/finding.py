"""Finding data models."""

from __future__ import annotations

from enum import Enum
from typing import Optional

from pydantic import BaseModel, Field


class Severity(str, Enum):
    BLOCKER = "BLOCKER"
    HIGH = "HIGH"
    MEDIUM = "MEDIUM"
    LOW = "LOW"


class Effort(str, Enum):
    S = "S"
    M = "M"
    L = "L"


class Finding(BaseModel):
    id: str = Field(pattern=r"^[A-Z]+-\d+$")
    title: str
    severity: Severity
    file: Optional[str] = None
    line: Optional[int] = None
    effort: Optional[Effort] = None
    issue: Optional[str] = None
    evidence: Optional[str] = None
    recommendation: Optional[str] = None


class FindingSummary(BaseModel):
    blockers: int = 0
    high: int = 0
    medium: int = 0
    low: int = 0
    total: int = 0
