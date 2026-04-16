"""Compliance mapping data models."""

from __future__ import annotations

from pydantic import BaseModel


class Control(BaseModel):
    """A single compliance control extracted from a standard."""

    id: str
    title: str
    domain_id: str
    domain_name: str
    agents: list[str] | None = None
    finding_patterns: list[str] | None = None
    critical: bool = False


class MappedFinding(BaseModel):
    """A finding matched to one or more controls."""

    finding_id: str
    finding_title: str
    finding_severity: str
    control_ids: list[str]


class DomainCoverage(BaseModel):
    """Coverage stats for one domain within a standard."""

    name: str
    total: int
    addressed: int
    gaps: int
    coverage: float


class ComplianceMapping(BaseModel):
    """Full compliance mapping result."""

    standard_id: str
    standard_name: str
    timestamp: str
    total_controls: int = 0
    addressed_controls: int = 0
    gapped_controls: int = 0
    coverage_percent: float = 0.0
    by_domain: dict[str, DomainCoverage] = {}
    mapped_findings: list[MappedFinding] = []
    gaps: list[Control] = []
    critical_gaps: list[Control] = []
