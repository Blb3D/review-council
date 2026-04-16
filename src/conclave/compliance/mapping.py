"""Compliance mapping engine.

Port of Get-AllControls, Test-FindingPattern, Match-FindingToControls,
Get-ComplianceMapping, Get-AgentControls from mapping-engine.ps1.
"""

from __future__ import annotations

import re
from collections import defaultdict
from datetime import datetime

from ..models.compliance import ComplianceMapping, Control, DomainCoverage, MappedFinding


def get_all_controls(standard: dict) -> list[Control]:
    """Extract all controls from a compliance standard.

    Handles both CMMC-style (domains) and FDA-style (subparts) structures.
    """
    controls: list[Control] = []

    # CMMC-style: domains -> controls
    for domain in standard.get("domains", []) or []:
        for ctrl in domain.get("controls", []) or []:
            controls.append(Control(
                id=ctrl["id"],
                title=ctrl.get("title", ""),
                domain_id=domain.get("id", ""),
                domain_name=domain.get("name", ""),
                agents=ctrl.get("agents"),
                finding_patterns=ctrl.get("finding_patterns"),
                critical=bool(ctrl.get("critical")),
            ))

    # FDA-style: subparts -> sections -> subsections
    for subpart in standard.get("subparts", []) or []:
        for section in subpart.get("sections", []) or []:
            subsections = section.get("subsections")
            if subsections:
                for subsection in subsections:
                    controls.append(Control(
                        id=subsection["id"],
                        title=subsection.get("title", ""),
                        domain_id=subpart.get("id", ""),
                        domain_name=subpart.get("name", ""),
                        agents=subsection.get("agents"),
                        finding_patterns=subsection.get("finding_patterns"),
                        critical=bool(subsection.get("critical")),
                    ))
            else:
                # Section without subsections is the control itself
                controls.append(Control(
                    id=section["id"],
                    title=section.get("title", ""),
                    domain_id=subpart.get("id", ""),
                    domain_name=subpart.get("name", ""),
                    agents=section.get("agents"),
                    finding_patterns=section.get("finding_patterns"),
                    critical=bool(section.get("critical")),
                ))

    return controls


def test_finding_pattern(finding_id: str, pattern: str) -> bool:
    """Test if a finding ID matches a pattern.

    Supports exact matches and wildcard patterns (e.g., GUARDIAN-*).
    """
    if "*" in pattern:
        regex = "^" + re.escape(pattern).replace(r"\*", ".*") + "$"
        return bool(re.match(regex, finding_id))
    return finding_id == pattern


def match_finding_to_controls(
    finding: dict,
    controls: list[Control],
) -> list[Control]:
    """Find all controls that a finding addresses."""
    matched: list[Control] = []
    finding_id = finding.get("id", "")

    for control in controls:
        if not control.finding_patterns:
            continue
        for pattern in control.finding_patterns:
            if test_finding_pattern(finding_id, pattern):
                matched.append(control)
                break

    return matched


def get_compliance_mapping(
    findings: list[dict],
    standard: dict,
) -> ComplianceMapping:
    """Generate a complete compliance mapping for findings against a standard."""
    all_controls = get_all_controls(standard)
    addressed_ids: set[str] = set()
    mapped_findings: list[MappedFinding] = []

    # Match findings to controls
    for finding in findings:
        matched = match_finding_to_controls(finding, all_controls)
        if matched:
            mapped_findings.append(MappedFinding(
                finding_id=finding.get("id", ""),
                finding_title=finding.get("title", ""),
                finding_severity=finding.get("severity", ""),
                control_ids=[c.id for c in matched],
            ))
            for ctrl in matched:
                addressed_ids.add(ctrl.id)

    # Identify gaps
    gaps = [c for c in all_controls if c.id not in addressed_ids]
    critical_gaps = [c for c in gaps if c.critical]

    total = len(all_controls)
    addressed = len(addressed_ids)
    coverage = round((addressed / total) * 100, 1) if total > 0 else 0.0

    # Domain coverage
    domain_groups: dict[str, list[Control]] = defaultdict(list)
    for ctrl in all_controls:
        domain_groups[ctrl.domain_id].append(ctrl)

    by_domain: dict[str, DomainCoverage] = {}
    for domain_id, domain_controls in sorted(domain_groups.items()):
        d_total = len(domain_controls)
        d_addressed = sum(1 for c in domain_controls if c.id in addressed_ids)
        by_domain[domain_id] = DomainCoverage(
            name=domain_controls[0].domain_name,
            total=d_total,
            addressed=d_addressed,
            gaps=d_total - d_addressed,
            coverage=round((d_addressed / d_total) * 100, 1) if d_total > 0 else 0.0,
        )

    return ComplianceMapping(
        standard_id=standard.get("id", ""),
        standard_name=standard.get("name", ""),
        timestamp=datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        total_controls=total,
        addressed_controls=addressed,
        gapped_controls=total - addressed,
        coverage_percent=coverage,
        by_domain=by_domain,
        mapped_findings=mapped_findings,
        gaps=gaps,
        critical_gaps=critical_gaps,
    )


def get_agent_controls(standard: dict, agent_key: str) -> list[Control]:
    """Get controls relevant to a specific agent."""
    all_controls = get_all_controls(standard)
    agent_lower = agent_key.lower()
    return [c for c in all_controls if c.agents and agent_lower in c.agents]
