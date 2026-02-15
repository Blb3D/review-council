"""Validator: post-processing step that stress-tests BLOCKER/HIGH findings.

Runs after all agents complete but before synthesis. Uses the AI to re-evaluate
high-severity findings against actual code context, access patterns, and
calibration data.
"""

from __future__ import annotations

import re
import time
from pathlib import Path
from typing import Optional

from rich.console import Console

from .agents import load_agent_instructions
from .calibration import build_calibration_context, load_calibration
from ..providers.base import AIProvider

console = Console()


def _collect_high_severity_findings(all_findings: dict[str, dict]) -> list[dict]:
    """Extract BLOCKER and HIGH findings from all agent results."""
    results = []
    for agent_key, agent_data in all_findings.items():
        for finding in agent_data.get("findings", []):
            severity = finding.get("severity", "").upper()
            if severity in ("BLOCKER", "HIGH"):
                results.append({
                    "agent": agent_key,
                    "finding_id": finding.get("id", ""),
                    "title": finding.get("title", ""),
                    "severity": severity,
                    "file": finding.get("file", ""),
                    "line": finding.get("line"),
                    "description": finding.get("description", ""),
                    "evidence": finding.get("evidence", ""),
                    "recommendation": finding.get("recommendation", ""),
                })
    return results


def _build_validation_prompt(findings: list[dict], calibration_context: str) -> str:
    """Build the user prompt listing findings to validate."""
    parts = ["# FINDINGS TO VALIDATE\n"]
    parts.append(
        "Validate each BLOCKER and HIGH finding below. "
        "Follow the 5-step decision tree from your instructions.\n"
    )

    for f in findings:
        parts.append(f"## {f['finding_id']}: {f['title']} [{f['severity']}]")
        parts.append(f"**Agent:** {f['agent'].upper()}")
        if f.get("file"):
            loc = f["file"]
            if f.get("line"):
                loc += f":{f['line']}"
            parts.append(f"**Location:** `{loc}`")
        if f.get("description"):
            parts.append(f"**Description:** {f['description']}")
        if f.get("evidence"):
            parts.append(f"**Evidence:**\n```\n{f['evidence']}\n```")
        if f.get("recommendation"):
            parts.append(f"**Recommendation:** {f['recommendation']}")
        parts.append("")

    if calibration_context:
        parts.append(calibration_context)

    parts.append(
        "\nValidate each finding above and output your assessment. "
        "End with: VALIDATION COMPLETE: X confirmed, Y downgraded, Z rejected out of N total"
    )

    return "\n".join(parts)


def _parse_validation_results(content: str) -> list[dict]:
    """Parse validator output into structured adjustments."""
    adjustments = []

    # Match: ### VALIDATE: GUARDIAN-002 — BLOCKER → LOW
    # Supports em-dash/en-dash/hyphen and arrow/unicode arrow variants
    pattern = (
        r"###\s+VALIDATE:\s+(\S+)\s*(?:—|–|-)\s*(BLOCKER|HIGH|MEDIUM|LOW)\s*"
        r"(?:→|->)\s*(BLOCKER|HIGH|MEDIUM|LOW|REJECTED)"
    )

    for m in re.finditer(pattern, content, re.IGNORECASE):
        finding_id = m.group(1)
        original = m.group(2).upper()
        adjusted = m.group(3).upper()

        # Determine decision type
        if adjusted == "REJECTED":
            decision = "rejected"
        elif adjusted == original:
            decision = "confirmed"
        else:
            decision = "downgraded"

        # Extract reason (look for **Reason:** after this match)
        reason_pattern = r"\*\*Reason:\*\*\s*(.+?)(?:\n\n|\n###|\Z)"
        reason_match = re.search(reason_pattern, content[m.end():], re.DOTALL)
        reason = reason_match.group(1).strip() if reason_match else ""

        adjustments.append({
            "finding_id": finding_id,
            "original_severity": original,
            "adjusted_severity": adjusted if adjusted != "REJECTED" else "REJECTED",
            "decision": decision,
            "reason": reason,
        })

    return adjustments


def _apply_adjustments(
    all_findings: dict[str, dict],
    adjustments: list[dict],
) -> tuple[dict[str, dict], dict]:
    """Apply validator adjustments to the findings data.

    Returns (adjusted_findings, adjustment_summary).
    """
    adjustment_map = {a["finding_id"]: a for a in adjustments}
    stats = {"confirmed": 0, "downgraded": 0, "rejected": 0, "total": len(adjustments)}

    for agent_key, agent_data in all_findings.items():
        adjusted_findings = []
        for finding in agent_data.get("findings", []):
            fid = finding.get("id", "")
            adj = adjustment_map.get(fid)

            if adj:
                stats[adj["decision"]] = stats.get(adj["decision"], 0) + 1

                if adj["decision"] == "rejected":
                    # Mark as rejected but keep in list with LOW severity
                    finding["original_severity"] = finding.get("severity", "")
                    finding["severity"] = "REJECTED"
                    finding["validated"] = "rejected"
                    finding["validation_reason"] = adj.get("reason", "")
                    # Don't include rejected findings in the list
                    continue
                elif adj["decision"] == "downgraded":
                    finding["original_severity"] = finding.get("severity", "")
                    finding["severity"] = adj["adjusted_severity"]
                    finding["validated"] = "downgraded"
                    finding["validation_reason"] = adj.get("reason", "")
                else:
                    finding["validated"] = "confirmed"

            adjusted_findings.append(finding)

        agent_data["findings"] = adjusted_findings

        # Recalculate summary
        summary = {"blockers": 0, "high": 0, "medium": 0, "low": 0, "total": 0}
        for f in adjusted_findings:
            sev = f.get("severity", "").upper()
            if sev == "BLOCKER":
                summary["blockers"] += 1
            elif sev == "HIGH":
                summary["high"] += 1
            elif sev == "MEDIUM":
                summary["medium"] += 1
            elif sev == "LOW":
                summary["low"] += 1
            summary["total"] += 1
        agent_data["summary"] = summary

    return all_findings, stats


async def run_validator(
    all_findings: dict[str, dict],
    shared_context: str,
    project_path: Path,
    provider: AIProvider,
    effective_config: dict,
    dry_run: bool = False,
) -> tuple[dict[str, dict], dict]:
    """Run the validator step on all BLOCKER/HIGH findings.

    Returns (adjusted_findings, validation_stats).
    """
    # Collect findings to validate
    high_severity = _collect_high_severity_findings(all_findings)

    if not high_severity:
        console.print("  [dim]No BLOCKER/HIGH findings to validate[/dim]")
        return all_findings, {"confirmed": 0, "downgraded": 0, "rejected": 0, "total": 0}

    console.print(
        f"\n  [cyan]Validating {len(high_severity)} BLOCKER/HIGH findings...[/cyan]"
    )

    if dry_run:
        # In dry-run, simulate validation (confirm everything)
        console.print("  [dim]DRY RUN: Skipping AI validation[/dim]")
        return all_findings, {
            "confirmed": len(high_severity),
            "downgraded": 0,
            "rejected": 0,
            "total": len(high_severity),
        }

    start = time.time()

    # Build calibration context
    # Combine calibration for all agents involved
    calibration_parts = []
    seen_agents = set()
    for f in high_severity:
        agent = f["agent"]
        if agent not in seen_agents:
            seen_agents.add(agent)
            ctx = build_calibration_context(project_path, agent)
            if ctx:
                calibration_parts.append(ctx)

    calibration_context = "\n\n".join(calibration_parts)

    # Load validator instructions
    validator_instructions = load_agent_instructions("validator", project_path)

    system_prompt = (
        "You are VALIDATOR, the finding validation specialist.\n\n"
        f"{validator_instructions}"
    )

    user_prompt = _build_validation_prompt(high_severity, calibration_context)

    # Call AI
    result = await provider.complete_with_retry(
        shared_context=shared_context,
        system_prompt=system_prompt,
        user_prompt=user_prompt,
        tier="primary",
    )

    duration = time.time() - start

    if not result.success:
        console.print(f"  [yellow]WARN[/yellow] Validator failed: {result.error}")
        console.print("  [dim]Proceeding with original findings[/dim]")
        return all_findings, {
            "confirmed": len(high_severity),
            "downgraded": 0,
            "rejected": 0,
            "total": len(high_severity),
        }

    # Save validator raw output for debugging
    val_output_path = project_path / ".code-conclave" / "reviews" / "validator-output.md"
    val_output_path.write_text(result.content or "", encoding="utf-8")

    # Parse and apply adjustments
    adjustments = _parse_validation_results(result.content or "")
    adjusted_findings, stats = _apply_adjustments(all_findings, adjustments)

    if not adjustments and result.content:
        console.print(
            f"  [yellow]WARN[/yellow] Validator produced output but no parseable adjustments. "
            f"See validator-output.md"
        )

    # Report
    console.print(
        f"  [green]OK[/green] Validator: "
        f"{stats['confirmed']} confirmed, "
        f"{stats['downgraded']} downgraded, "
        f"{stats['rejected']} rejected "
        f"in {round(duration, 1)}s"
    )

    return adjusted_findings, stats
