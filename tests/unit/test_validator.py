"""Tests for the validator module."""

import pytest
from pathlib import Path

from conclave.core.validator import (
    _apply_adjustments,
    _build_validation_prompt,
    _collect_high_severity_findings,
    _parse_validation_results,
)


class TestCollectHighSeverity:
    def test_collects_blocker_and_high(self):
        all_findings = {
            "guardian": {
                "findings": [
                    {"id": "GUARDIAN-001", "severity": "BLOCKER", "title": "SQL Injection", "file": "app.py"},
                    {"id": "GUARDIAN-002", "severity": "HIGH", "title": "Weak Hash", "file": "auth.py"},
                    {"id": "GUARDIAN-003", "severity": "MEDIUM", "title": "Missing CORS", "file": "api.py"},
                    {"id": "GUARDIAN-004", "severity": "LOW", "title": "Old dep", "file": "req.txt"},
                ],
            },
        }
        results = _collect_high_severity_findings(all_findings)
        assert len(results) == 2
        assert results[0]["finding_id"] == "GUARDIAN-001"
        assert results[1]["finding_id"] == "GUARDIAN-002"

    def test_empty_findings(self):
        assert _collect_high_severity_findings({}) == []
        assert _collect_high_severity_findings({"guardian": {"findings": []}}) == []

    def test_multiple_agents(self):
        all_findings = {
            "guardian": {
                "findings": [
                    {"id": "GUARDIAN-001", "severity": "BLOCKER", "title": "Issue A"},
                ],
            },
            "sentinel": {
                "findings": [
                    {"id": "SENTINEL-001", "severity": "HIGH", "title": "Issue B"},
                    {"id": "SENTINEL-002", "severity": "MEDIUM", "title": "Issue C"},
                ],
            },
        }
        results = _collect_high_severity_findings(all_findings)
        assert len(results) == 2
        ids = {r["finding_id"] for r in results}
        assert ids == {"GUARDIAN-001", "SENTINEL-001"}


class TestBuildValidationPrompt:
    def test_includes_findings(self):
        findings = [
            {
                "agent": "guardian",
                "finding_id": "GUARDIAN-001",
                "title": "SQL Injection",
                "severity": "BLOCKER",
                "file": "app.py",
                "line": 42,
                "description": "Raw SQL used",
                "evidence": "query = f\"SELECT...\"",
                "recommendation": "Use parameterized queries",
            }
        ]
        prompt = _build_validation_prompt(findings, "")
        assert "GUARDIAN-001" in prompt
        assert "SQL Injection" in prompt
        assert "BLOCKER" in prompt
        assert "app.py:42" in prompt

    def test_includes_calibration(self):
        findings = [{"agent": "g", "finding_id": "G-1", "title": "X", "severity": "HIGH",
                      "file": "", "line": None, "description": "", "evidence": "", "recommendation": ""}]
        prompt = _build_validation_prompt(findings, "# CALIBRATION\nSome data here")
        assert "CALIBRATION" in prompt


class TestParseValidationResults:
    def test_parse_confirmed(self):
        content = """
### VALIDATE: GUARDIAN-001 — BLOCKER → BLOCKER

**Original:** SQL injection in search
**File:** `app.py:42`

**Decision:** CONFIRMED
**Adjusted severity:** BLOCKER
**Reason:** Raw string interpolation in SQL query, no parameterization.

VALIDATION COMPLETE: 1 confirmed, 0 downgraded, 0 rejected out of 1 total
"""
        results = _parse_validation_results(content)
        assert len(results) == 1
        assert results[0]["finding_id"] == "GUARDIAN-001"
        assert results[0]["decision"] == "confirmed"
        assert results[0]["adjusted_severity"] == "BLOCKER"

    def test_parse_downgraded(self):
        content = """
### VALIDATE: GUARDIAN-002 — BLOCKER → LOW

**Decision:** DOWNGRADED
**Adjusted severity:** LOW
**Reason:** Admin-only endpoint, ORM parameterized query.
"""
        results = _parse_validation_results(content)
        assert len(results) == 1
        assert results[0]["decision"] == "downgraded"
        assert results[0]["adjusted_severity"] == "LOW"
        assert "Admin-only" in results[0]["reason"]

    def test_parse_rejected(self):
        content = """
### VALIDATE: SENTINEL-003 — HIGH → REJECTED

**Decision:** REJECTED
**Adjusted severity:** REJECTED
**Reason:** Cited file doesn't match actual code.
"""
        results = _parse_validation_results(content)
        assert len(results) == 1
        assert results[0]["decision"] == "rejected"
        assert results[0]["adjusted_severity"] == "REJECTED"

    def test_parse_multiple(self):
        content = """
### VALIDATE: GUARDIAN-001 — BLOCKER → BLOCKER
**Reason:** Confirmed real issue.

### VALIDATE: GUARDIAN-002 — BLOCKER → LOW
**Reason:** Over-rated, admin only.

### VALIDATE: SENTINEL-001 — HIGH → REJECTED
**Reason:** False positive.

VALIDATION COMPLETE: 1 confirmed, 1 downgraded, 1 rejected out of 3 total
"""
        results = _parse_validation_results(content)
        assert len(results) == 3
        decisions = [r["decision"] for r in results]
        assert decisions == ["confirmed", "downgraded", "rejected"]

    def test_parse_with_arrow_variants(self):
        """Handle different arrow styles."""
        content = "### VALIDATE: G-001 — HIGH -> MEDIUM\n**Reason:** Downgraded.\n"
        results = _parse_validation_results(content)
        assert len(results) == 1
        assert results[0]["adjusted_severity"] == "MEDIUM"


class TestApplyAdjustments:
    def _make_findings(self):
        return {
            "guardian": {
                "findings": [
                    {"id": "GUARDIAN-001", "severity": "BLOCKER", "title": "Real issue"},
                    {"id": "GUARDIAN-002", "severity": "BLOCKER", "title": "ORM wildcard"},
                    {"id": "GUARDIAN-003", "severity": "HIGH", "title": "Fabricated"},
                ],
                "summary": {"blockers": 2, "high": 1, "medium": 0, "low": 0, "total": 3},
            },
        }

    def test_confirmed_unchanged(self):
        findings = self._make_findings()
        adjustments = [
            {"finding_id": "GUARDIAN-001", "original_severity": "BLOCKER",
             "adjusted_severity": "BLOCKER", "decision": "confirmed", "reason": "Real"},
        ]
        adjusted, stats = _apply_adjustments(findings, adjustments)
        assert stats["confirmed"] == 1
        g001 = next(f for f in adjusted["guardian"]["findings"] if f["id"] == "GUARDIAN-001")
        assert g001["severity"] == "BLOCKER"
        assert g001["validated"] == "confirmed"

    def test_downgraded(self):
        findings = self._make_findings()
        adjustments = [
            {"finding_id": "GUARDIAN-002", "original_severity": "BLOCKER",
             "adjusted_severity": "LOW", "decision": "downgraded", "reason": "Admin only"},
        ]
        adjusted, stats = _apply_adjustments(findings, adjustments)
        assert stats["downgraded"] == 1
        g002 = next(f for f in adjusted["guardian"]["findings"] if f["id"] == "GUARDIAN-002")
        assert g002["severity"] == "LOW"
        assert g002["original_severity"] == "BLOCKER"
        assert g002["validated"] == "downgraded"

    def test_rejected_removed(self):
        findings = self._make_findings()
        adjustments = [
            {"finding_id": "GUARDIAN-003", "original_severity": "HIGH",
             "adjusted_severity": "REJECTED", "decision": "rejected", "reason": "Fabricated"},
        ]
        adjusted, stats = _apply_adjustments(findings, adjustments)
        assert stats["rejected"] == 1
        # Rejected findings are removed from the list
        ids = [f["id"] for f in adjusted["guardian"]["findings"]]
        assert "GUARDIAN-003" not in ids

    def test_summary_recalculated(self):
        findings = self._make_findings()
        adjustments = [
            {"finding_id": "GUARDIAN-002", "original_severity": "BLOCKER",
             "adjusted_severity": "LOW", "decision": "downgraded", "reason": ""},
            {"finding_id": "GUARDIAN-003", "original_severity": "HIGH",
             "adjusted_severity": "REJECTED", "decision": "rejected", "reason": ""},
        ]
        adjusted, stats = _apply_adjustments(findings, adjustments)
        summary = adjusted["guardian"]["summary"]
        assert summary["blockers"] == 1  # Only GUARDIAN-001 remains as BLOCKER
        assert summary["low"] == 1       # GUARDIAN-002 downgraded to LOW
        assert summary["high"] == 0      # GUARDIAN-003 rejected
        assert summary["total"] == 2     # 3 - 1 rejected = 2

    def test_no_adjustments(self):
        findings = self._make_findings()
        adjusted, stats = _apply_adjustments(findings, [])
        assert stats["total"] == 0
        # Original findings unchanged
        assert len(adjusted["guardian"]["findings"]) == 3
