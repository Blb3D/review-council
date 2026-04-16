"""Agent data models."""

from __future__ import annotations

from typing import Optional

from pydantic import BaseModel

from .finding import Finding, FindingSummary


class AgentDef(BaseModel):
    key: str
    name: str
    role: str
    color: str = "white"
    tier: str = "primary"


class AgentResult(BaseModel):
    agent: AgentDef
    status: str = "complete"
    summary: FindingSummary = FindingSummary()
    findings: list[Finding] = []
    raw_markdown: str = ""
    duration_seconds: float = 0
    tokens: Optional[dict] = None
    error: Optional[str] = None
