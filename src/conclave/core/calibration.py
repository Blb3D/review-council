"""Calibration system: per-project feedback that improves future reviews.

Stores human-reviewed findings (confirmed/false-positive) and injects them
as few-shot examples into agent prompts.

Calibration file: .code-conclave/calibration.yaml
"""

from __future__ import annotations

import re
from datetime import datetime
from pathlib import Path
from typing import Optional

import yaml


def load_calibration(project_path: Path) -> dict:
    """Load calibration data from .code-conclave/calibration.yaml."""
    cal_path = project_path / ".code-conclave" / "calibration.yaml"
    if not cal_path.exists():
        return {"reviewed_findings": [], "project_rules": []}
    try:
        content = cal_path.read_text(encoding="utf-8-sig")
        data = yaml.safe_load(content) or {}
        # Ensure expected keys
        data.setdefault("reviewed_findings", [])
        data.setdefault("project_rules", [])
        return data
    except Exception:
        return {"reviewed_findings": [], "project_rules": []}


def save_calibration(project_path: Path, calibration: dict) -> Path:
    """Save calibration data to .code-conclave/calibration.yaml."""
    cal_path = project_path / ".code-conclave" / "calibration.yaml"
    cal_path.parent.mkdir(parents=True, exist_ok=True)

    content = yaml.dump(
        calibration,
        default_flow_style=False,
        sort_keys=False,
        allow_unicode=True,
        width=120,
    )
    cal_path.write_text(content, encoding="utf-8")
    return cal_path


def add_reviewed_finding(
    project_path: Path,
    finding_id: str,
    agent: str,
    original_severity: str,
    adjusted_severity: str,
    verdict: str,
    reason: str,
    file_path: Optional[str] = None,
    title: Optional[str] = None,
) -> dict:
    """Add a human-reviewed finding to calibration data.

    Args:
        verdict: 'confirmed', 'false_positive', or 'adjusted'
    """
    calibration = load_calibration(project_path)

    entry = {
        "finding_id": finding_id,
        "agent": agent,
        "title": title or "",
        "file": file_path or "",
        "original_severity": original_severity.upper(),
        "adjusted_severity": adjusted_severity.upper(),
        "verdict": verdict,
        "reason": reason,
        "reviewed_at": datetime.now().strftime("%Y-%m-%d"),
    }

    # Replace if same finding_id exists
    calibration["reviewed_findings"] = [
        f for f in calibration["reviewed_findings"]
        if f.get("finding_id") != finding_id
    ]
    calibration["reviewed_findings"].append(entry)

    save_calibration(project_path, calibration)
    return entry


def add_project_rule(
    project_path: Path,
    rule: str,
    applies_to: str = "all",
    severity_cap: Optional[str] = None,
) -> dict:
    """Add a project-specific rule to calibration.

    Example rules:
      - "All endpoints under /api/v1/admin/ are admin-only behind JWT auth"
      - "This project uses SQLAlchemy ORM exclusively, no raw SQL"
    """
    calibration = load_calibration(project_path)

    entry = {
        "rule": rule,
        "applies_to": applies_to,  # 'all', 'guardian', 'sentinel', etc.
        "severity_cap": severity_cap,  # Optional: cap severity for matching findings
        "added_at": datetime.now().strftime("%Y-%m-%d"),
    }

    calibration["project_rules"].append(entry)
    save_calibration(project_path, calibration)
    return entry


def build_calibration_context(project_path: Path, agent_key: str) -> str:
    """Build calibration context to inject into an agent prompt.

    Returns a markdown section with reviewed findings and project rules
    relevant to this agent.
    """
    calibration = load_calibration(project_path)
    sections: list[str] = []

    # Project-specific rules
    rules = calibration.get("project_rules", [])
    relevant_rules = [
        r for r in rules
        if r.get("applies_to", "all") in ("all", agent_key)
    ]
    if relevant_rules:
        sections.append("## Project-Specific Rules\n")
        sections.append("The following rules have been established for this project:\n")
        for r in relevant_rules:
            line = f"- {r['rule']}"
            if r.get("severity_cap"):
                line += f" (severity cap: {r['severity_cap']})"
            sections.append(line)
        sections.append("")

    # Reviewed findings as few-shot examples
    reviewed = calibration.get("reviewed_findings", [])
    relevant = [
        f for f in reviewed
        if f.get("agent", "").lower() == agent_key.lower()
    ]

    false_positives = [f for f in relevant if f.get("verdict") == "false_positive"]
    adjusted = [f for f in relevant if f.get("verdict") == "adjusted"]
    confirmed = [f for f in relevant if f.get("verdict") == "confirmed"]

    if false_positives:
        sections.append("## Previous False Positives (DO NOT repeat these)\n")
        sections.append(
            "These findings were previously flagged but a human reviewer "
            "determined they were false positives. Do NOT repeat them:\n"
        )
        for f in false_positives[-10:]:  # Last 10 most recent
            sections.append(
                f"- **{f.get('finding_id', '?')}**: \"{f.get('title', '')}\" "
                f"at `{f.get('file', '?')}` — "
                f"was {f['original_severity']}, "
                f"REJECTED because: {f.get('reason', 'no reason given')}"
            )
        sections.append("")

    if adjusted:
        sections.append("## Previous Severity Adjustments (calibrate accordingly)\n")
        sections.append(
            "These findings were flagged at the wrong severity. "
            "Use these as calibration examples:\n"
        )
        for f in adjusted[-10:]:
            sections.append(
                f"- **{f.get('finding_id', '?')}**: \"{f.get('title', '')}\" "
                f"at `{f.get('file', '?')}` — "
                f"was {f['original_severity']}, adjusted to {f['adjusted_severity']} "
                f"because: {f.get('reason', 'no reason given')}"
            )
        sections.append("")

    if confirmed:
        sections.append("## Confirmed True Positives (good catches)\n")
        sections.append("These were correctly identified. Look for similar patterns:\n")
        for f in confirmed[-5:]:
            sections.append(
                f"- **{f.get('finding_id', '?')}**: \"{f.get('title', '')}\" "
                f"at `{f.get('file', '?')}` [{f['original_severity']}] — confirmed"
            )
        sections.append("")

    if not sections:
        return ""

    return "# CALIBRATION DATA (from previous human reviews)\n\n" + "\n".join(sections)
