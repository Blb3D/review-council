"""Tests for core/synthesis.py."""

from __future__ import annotations

from conclave.core.synthesis import calculate_verdict, generate_synthesis_report, get_exit_code
from conclave.models.review import Verdict


class TestCalculateVerdict:
    def test_ship_no_issues(self):
        findings = {
            "guardian": {
                "summary": {"blockers": 0, "high": 0, "medium": 1, "low": 2, "total": 3},
                "findings": [],
            }
        }
        assert calculate_verdict(findings) == Verdict.SHIP

    def test_hold_on_blocker(self):
        findings = {
            "guardian": {
                "summary": {"blockers": 1, "high": 0, "medium": 0, "low": 0, "total": 1},
                "findings": [],
            }
        }
        assert calculate_verdict(findings) == Verdict.HOLD

    def test_conditional_on_many_high(self):
        findings = {
            "guardian": {
                "summary": {"blockers": 0, "high": 4, "medium": 0, "low": 0, "total": 4},
                "findings": [],
            }
        }
        assert calculate_verdict(findings) == Verdict.CONDITIONAL

    def test_ship_with_few_high(self):
        findings = {
            "guardian": {
                "summary": {"blockers": 0, "high": 2, "medium": 1, "low": 0, "total": 3},
                "findings": [],
            }
        }
        assert calculate_verdict(findings) == Verdict.SHIP

    def test_hold_beats_conditional(self):
        findings = {
            "guardian": {
                "summary": {"blockers": 1, "high": 10, "medium": 0, "low": 0, "total": 11},
                "findings": [],
            }
        }
        assert calculate_verdict(findings) == Verdict.HOLD

    def test_aggregates_across_agents(self):
        findings = {
            "guardian": {
                "summary": {"blockers": 0, "high": 2, "medium": 0, "low": 0, "total": 2},
                "findings": [],
            },
            "sentinel": {
                "summary": {"blockers": 0, "high": 2, "medium": 0, "low": 0, "total": 2},
                "findings": [],
            },
        }
        # 4 total HIGH > 3 threshold => CONDITIONAL
        assert calculate_verdict(findings) == Verdict.CONDITIONAL

    def test_empty_findings(self):
        assert calculate_verdict({}) == Verdict.SHIP


class TestGetExitCode:
    def test_ship_is_zero(self):
        assert get_exit_code(Verdict.SHIP) == 0

    def test_hold_is_one(self):
        assert get_exit_code(Verdict.HOLD) == 1

    def test_conditional_is_two(self):
        assert get_exit_code(Verdict.CONDITIONAL) == 2


class TestGenerateSynthesisReport:
    def test_generates_markdown(self, sample_all_findings: dict):
        report = generate_synthesis_report(
            sample_all_findings,
            project_name="test-project",
            project_path="/tmp/test",
            duration_seconds=10.5,
            provider="anthropic",
        )
        assert "# RELEASE READINESS REPORT" in report or "RELEASE" in report.upper()
        assert "test-project" in report

    def test_includes_verdict(self, sample_all_findings: dict):
        report = generate_synthesis_report(
            sample_all_findings,
            project_name="test-project",
            project_path="/tmp/test",
        )
        # Should contain one of the verdict values
        assert any(v in report for v in ["SHIP", "CONDITIONAL", "HOLD"])

    def test_dry_run_noted(self, sample_all_findings: dict):
        report = generate_synthesis_report(
            sample_all_findings,
            project_name="test-project",
            project_path="/tmp/test",
            dry_run=True,
        )
        assert "DRY RUN" in report.upper() or "dry-run" in report.lower()
