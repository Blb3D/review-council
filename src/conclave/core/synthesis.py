"""Synthesis report generation and verdict logic.

Port of the New-SynthesisReport function from ccl.ps1.
"""

from __future__ import annotations

from datetime import datetime
from pathlib import Path
from typing import Optional

from ..models.review import Verdict


def calculate_verdict(all_findings: dict[str, dict]) -> Verdict:
    """Calculate the review verdict from agent findings.

    - HOLD: any BLOCKER
    - CONDITIONAL: no blockers but >3 HIGH
    - SHIP: everything else
    """
    total_blockers = 0
    total_high = 0

    for agent_data in all_findings.values():
        if not agent_data or not agent_data.get("summary"):
            continue
        summary = agent_data["summary"]
        total_blockers += int(summary.get("blockers", 0))
        total_high += int(summary.get("high", 0))

    if total_blockers > 0:
        return Verdict.HOLD
    if total_high > 3:
        return Verdict.CONDITIONAL
    return Verdict.SHIP


def get_exit_code(verdict: Verdict) -> int:
    """Map verdict to exit code."""
    return {
        Verdict.SHIP: 0,
        Verdict.CONDITIONAL: 2,
        Verdict.HOLD: 1,
    }.get(verdict, 0)


def generate_synthesis_report(
    all_findings: dict[str, dict],
    project_name: str = "",
    project_path: str = "",
    duration_seconds: float = 0,
    provider: str = "",
    standard: Optional[str] = None,
    dry_run: bool = False,
) -> str:
    """Generate the RELEASE-READINESS-REPORT.md synthesis report."""
    verdict = calculate_verdict(all_findings)

    # Aggregate totals
    totals = {"blockers": 0, "high": 0, "medium": 0, "low": 0, "total": 0}
    for agent_data in all_findings.values():
        if not agent_data or not agent_data.get("summary"):
            continue
        s = agent_data["summary"]
        totals["blockers"] += int(s.get("blockers", 0))
        totals["high"] += int(s.get("high", 0))
        totals["medium"] += int(s.get("medium", 0))
        totals["low"] += int(s.get("low", 0))
        totals["total"] += int(s.get("total", 0))

    verdict_emoji = {"SHIP": "PASS", "CONDITIONAL": "REVIEW", "HOLD": "FAIL"}
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    lines: list[str] = []
    lines.append("# Release Readiness Report")
    lines.append("")
    lines.append(f"**Project:** {project_name or project_path}")
    lines.append(f"**Date:** {timestamp}")
    lines.append(f"**Verdict:** {verdict_emoji.get(verdict.value, '?')} ({verdict.value})")
    if provider:
        lines.append(f"**Provider:** {provider}")
    if standard:
        lines.append(f"**Standard:** {standard}")
    if dry_run:
        lines.append("**Mode:** DRY RUN (mock findings)")
    lines.append(f"**Duration:** {round(duration_seconds, 1)}s")
    lines.append("")

    # Summary table
    lines.append("## Summary")
    lines.append("")
    lines.append("| Severity | Count |")
    lines.append("|----------|-------|")
    lines.append(f"| BLOCKER  | {totals['blockers']} |")
    lines.append(f"| HIGH     | {totals['high']} |")
    lines.append(f"| MEDIUM   | {totals['medium']} |")
    lines.append(f"| LOW      | {totals['low']} |")
    lines.append(f"| **Total** | **{totals['total']}** |")
    lines.append("")

    # Agent breakdown
    lines.append("## Agent Results")
    lines.append("")
    lines.append("| Agent | Role | Findings | Blockers | High | Duration |")
    lines.append("|-------|------|----------|----------|------|----------|")

    for agent_key, agent_data in all_findings.items():
        if not agent_data:
            continue
        agent_info = agent_data.get("agent", {})
        summary = agent_data.get("summary", {})
        run_info = agent_data.get("run", {})

        name = agent_info.get("name", agent_key.upper())
        role = agent_info.get("role", "")
        total = int(summary.get("total", 0))
        blockers = int(summary.get("blockers", 0))
        high = int(summary.get("high", 0))
        dur = round(float(run_info.get("durationSeconds", 0)), 1)

        lines.append(f"| {name} | {role} | {total} | {blockers} | {high} | {dur}s |")

    lines.append("")

    # Detailed findings by severity
    all_sorted: list[dict] = []
    for agent_key, agent_data in all_findings.items():
        if not agent_data:
            continue
        for f in agent_data.get("findings", []):
            f_copy = dict(f)
            f_copy["_agent"] = agent_key
            all_sorted.append(f_copy)

    severity_order = {"BLOCKER": 0, "HIGH": 1, "MEDIUM": 2, "LOW": 3}
    all_sorted.sort(key=lambda f: severity_order.get(f.get("severity", "LOW"), 4))

    if all_sorted:
        lines.append("## Findings Detail")
        lines.append("")
        for f in all_sorted:
            sev = f.get("severity", "?")
            fid = f.get("id", "?")
            title = f.get("title", "?")
            lines.append(f"### {fid}: {title} [{sev}]")
            if f.get("file"):
                loc = f["file"]
                if f.get("line"):
                    loc += f":{f['line']}"
                lines.append(f"**Location:** `{loc}`")
            if f.get("effort"):
                lines.append(f"**Effort:** {f['effort']}")
            if f.get("issue"):
                lines.append(f"\n{f['issue']}")
            lines.append("")

    lines.append("---")
    lines.append(f"*Generated by Code Conclave v3.0.0 at {timestamp}*")

    return "\n".join(lines)
