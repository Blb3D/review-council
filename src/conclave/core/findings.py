"""Findings parser: converts AI markdown output to structured data.

Port of cli/lib/findings-parser.ps1.
"""

from __future__ import annotations

import json
import math
import re
from datetime import datetime
from pathlib import Path
from typing import Optional


def _get_code_block_ranges(content: str) -> list[tuple[int, int]]:
    """Find all code block regions (```...```) in content."""
    ranges: list[tuple[int, int]] = []
    for m in re.finditer(r"```[\s\S]*?```", content):
        ranges.append((m.start(), m.end()))
    return ranges


def _in_code_block(pos: int, ranges: list[tuple[int, int]]) -> bool:
    """Check if a position falls inside a code block."""
    for start, end in ranges:
        if start <= pos < end:
            return True
    return False


def _get_section_text(content: str, header: str) -> Optional[str]:
    """Extract text from a markdown section header within a finding."""
    pattern = (
        rf"(?:\*\*)?{header}(?:\*\*)?:?\*?\*?\s*\r?\n"
        r"([\s\S]*?)"
        r"(?=\r?\n\*\*[A-Z]|\r?\n---|\Z)"
    )
    m = re.search(pattern, content)
    if not m:
        return None
    text = m.group(1).strip()
    text = re.sub(r"^\s*```[a-z]*\s*\r?\n", "", text)
    text = re.sub(r"\r?\n\s*```\s*$", "", text)
    return text.strip() or None


def parse_findings_markdown(
    content: str,
    agent_key: str,
    agent_name: str = "",
    agent_role: str = "",
    run_timestamp: Optional[str] = None,
    project_name: str = "",
    project_path: str = "",
    duration_seconds: float = 0,
    tokens_used: Optional[dict] = None,
    tier: str = "primary",
    dry_run: bool = False,
) -> dict:
    """Parse AI markdown output into structured findings data."""
    if not run_timestamp:
        run_timestamp = datetime.now().strftime("%Y-%m-%dT%H:%M:%S")

    code_block_ranges = _get_code_block_ranges(content)

    findings: list[dict] = []
    pattern = r"###\s+([A-Z]+-\d+):\s*(.+?)\s*\[(BLOCKER|HIGH|MEDIUM|LOW)\]"

    for match in re.finditer(pattern, content):
        if _in_code_block(match.start(), code_block_ranges):
            continue

        finding_id = match.group(1)
        title = match.group(2).strip()
        severity = match.group(3)

        # Extract section between this header and the next ### or end
        start_pos = match.end()
        next_header = content.find("###", start_pos)
        end_pos = next_header if next_header >= 0 else len(content)
        section = content[start_pos:end_pos]

        # Location/File
        file_val: Optional[str] = None
        line_val: Optional[int] = None

        loc_match = re.search(
            r"(?:\*\*)?(?:Location|File)(?:\*\*)?:?\*?\*?\s*`?([^\s`\r\n*]+(?::[^\s`\r\n*]*)?)`?",
            section,
        )
        if loc_match:
            loc = loc_match.group(1)
            line_check = re.match(r"^(.+):(\d+)$", loc)
            if line_check:
                file_val = line_check.group(1)
                line_val = int(line_check.group(2))
            else:
                file_val = loc

        # Line (separate field)
        if line_val is None:
            line_match = re.search(
                r"(?:\*\*)?Line(?:\*\*)?:?\*?\*?\s*(\d+)", section
            )
            if line_match:
                line_val = int(line_match.group(1))

        # Effort
        effort_val: Optional[str] = None
        effort_match = re.search(
            r"(?:\*\*)?Effort(?:\*\*)?:?\*?\*?\s*([SML])\b", section
        )
        if effort_match:
            effort_val = effort_match.group(1)

        # Section-based extraction
        issue = _get_section_text(section, "Issue")
        evidence = _get_section_text(section, "Evidence")
        recommendation = _get_section_text(
            section, "(?:Recommendation|Remediation)"
        )

        # Fallback: use remaining text as issue
        if not issue:
            plain = re.sub(
                r"\*\*(?:Location|File|Line|Effort|Evidence|Recommendation|Remediation|Issue)(?:\*\*)?:?[^\r\n]*",
                "",
                section,
            )
            plain = re.sub(r"```[\s\S]*?```", "", plain)
            plain = plain.replace("---", "").strip()
            if plain:
                issue = plain

        finding: dict = {
            "id": finding_id,
            "title": title,
            "severity": severity,
        }
        if file_val:
            finding["file"] = file_val
        if line_val is not None:
            finding["line"] = line_val
        if effort_val:
            finding["effort"] = effort_val
        if issue:
            finding["issue"] = issue
        if evidence:
            finding["evidence"] = evidence
        if recommendation:
            finding["recommendation"] = recommendation

        findings.append(finding)

    # Summary
    summary = {
        "blockers": sum(1 for f in findings if f["severity"] == "BLOCKER"),
        "high": sum(1 for f in findings if f["severity"] == "HIGH"),
        "medium": sum(1 for f in findings if f["severity"] == "MEDIUM"),
        "low": sum(1 for f in findings if f["severity"] == "LOW"),
        "total": len(findings),
    }

    # Tokens
    tokens = None
    if tokens_used:
        tokens = {}
        for key in ("input", "output", "cacheRead", "cacheWrite"):
            if tokens_used.get(key):
                tokens[key] = int(tokens_used[key])
        # Also accept PascalCase keys from PS
        for ps_key, py_key in [("Input", "input"), ("Output", "output"),
                                ("CacheRead", "cacheRead"), ("CacheWrite", "cacheWrite")]:
            if ps_key in tokens_used and py_key not in tokens:
                tokens[py_key] = int(tokens_used[ps_key])

    result: dict = {
        "version": "1.0.0",
        "agent": {
            "id": agent_key,
            "name": agent_name or agent_key.upper(),
            "role": agent_role or "",
            "tier": tier,
        },
        "run": {
            "timestamp": run_timestamp,
            "project": project_name or "",
            "projectPath": project_path or "",
            "durationSeconds": round(duration_seconds, 2),
            "dryRun": dry_run,
        },
        "status": "complete",
        "summary": summary,
        "findings": findings,
        "rawMarkdown": content,
    }

    if tokens:
        result["tokens"] = tokens

    return result


def export_findings_json(findings: dict, output_path: Path) -> Path:
    """Write findings data to a JSON file (UTF-8, no BOM)."""
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(
        json.dumps(findings, indent=2, ensure_ascii=False),
        encoding="utf-8",
    )
    return output_path


def export_run_archive(
    reviews_dir: Path,
    agent_findings: dict[str, dict],
    run_metadata: dict,
) -> Path:
    """Archive a completed run into a single timestamped JSON file."""
    archive_dir = reviews_dir / "archive"
    archive_dir.mkdir(parents=True, exist_ok=True)

    ts = run_metadata.get("timestamp", datetime.now())
    if isinstance(ts, datetime):
        ts_str = ts.strftime("%Y%m%dT%H%M%S")
        ts_iso = ts.strftime("%Y-%m-%dT%H:%M:%S")
    else:
        ts_str = datetime.now().strftime("%Y%m%dT%H%M%S")
        ts_iso = str(ts)

    # Aggregate summary
    total_b = total_h = total_m = total_l = 0
    for af in agent_findings.values():
        if af and af.get("summary"):
            total_b += int(af["summary"].get("blockers", 0))
            total_h += int(af["summary"].get("high", 0))
            total_m += int(af["summary"].get("medium", 0))
            total_l += int(af["summary"].get("low", 0))

    # Build agents section (strip rawMarkdown to keep archive small)
    agents_data: dict = {}
    for key, af in agent_findings.items():
        if not af:
            continue
        entry: dict = {
            "name": af.get("agent", {}).get("name", key.upper()),
            "role": af.get("agent", {}).get("role", ""),
            "tier": af.get("agent", {}).get("tier", "primary"),
            "status": af.get("status", "complete"),
            "summary": af.get("summary", {}),
            "findings": af.get("findings", []),
        }
        if af.get("tokens"):
            entry["tokens"] = af["tokens"]
        run_info = af.get("run", {})
        if run_info.get("durationSeconds"):
            entry["durationSeconds"] = run_info["durationSeconds"]
        agents_data[key] = entry

    duration = run_metadata.get("duration", 0)
    if isinstance(duration, (int, float)):
        duration = round(float(duration), 2)
    else:
        duration = 0

    archive = {
        "version": "1.0.0",
        "run": {
            "id": ts_str,
            "timestamp": ts_iso,
            "project": str(run_metadata.get("project", "")),
            "projectPath": str(run_metadata.get("project_path", "")),
            "durationSeconds": duration,
            "dryRun": bool(run_metadata.get("dry_run", False)),
            "baseBranch": run_metadata.get("base_branch"),
            "standard": run_metadata.get("standard"),
            "provider": str(run_metadata.get("provider", "unknown")),
            "agentsRequested": list(run_metadata.get("agents_requested", [])),
        },
        "verdict": run_metadata.get("verdict", "UNKNOWN"),
        "exitCode": int(run_metadata.get("exit_code", 0)),
        "summary": {
            "blockers": total_b,
            "high": total_h,
            "medium": total_m,
            "low": total_l,
            "total": total_b + total_h + total_m + total_l,
        },
        "agents": agents_data,
    }

    archive_path = archive_dir / f"{ts_str}.json"
    archive_path.write_text(
        json.dumps(archive, indent=2, ensure_ascii=False),
        encoding="utf-8",
    )
    return archive_path


def _load_latest_findings(project_path: Path, finding_id: str) -> Optional[dict]:
    """Look up a specific finding by ID from the latest review results.

    Searches all agent JSON files in the reviews directory.
    Returns the finding dict or None.
    """
    reviews_dir = project_path / ".code-conclave" / "reviews"
    if not reviews_dir.exists():
        return None

    # Search agent JSON files
    for json_file in reviews_dir.glob("*-findings.json"):
        try:
            content = json_file.read_text(encoding="utf-8")
            data = json.loads(content)
            for finding in data.get("findings", []):
                if finding.get("id", "").upper() == finding_id.upper():
                    # Add agent key from the file
                    finding["agent"] = json_file.stem.replace("-findings", "")
                    return finding
        except Exception:
            continue

    return None


def remove_working_findings(reviews_dir: Path) -> None:
    """Clean up working findings files after archival."""
    for pattern in ("*-findings.json", "*-findings.md"):
        for f in reviews_dir.glob(pattern):
            f.unlink(missing_ok=True)
    for name in ("RELEASE-READINESS-REPORT.md", "conclave-results.xml"):
        path = reviews_dir / name
        if path.exists():
            path.unlink(missing_ok=True)
