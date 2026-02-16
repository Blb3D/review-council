"""Tests for CLI entry points."""

from __future__ import annotations

from unittest.mock import AsyncMock, patch

import pytest
from click.testing import CliRunner

from conclave.cli.ccl import ccl_cli
from conclave.cli.rc import rc_cli


class TestRcCli:
    def test_requires_project(self):
        runner = CliRunner()
        result = runner.invoke(rc_cli, [])
        assert result.exit_code != 0
        assert "Missing" in result.output or "required" in result.output.lower() or result.exit_code == 2

    @patch("conclave.core.orchestrator.run_review", new_callable=AsyncMock)
    def test_runs_with_project(self, mock_review, tmp_path):
        mock_review.return_value = 0
        project = tmp_path / "proj"
        project.mkdir()

        runner = CliRunner()
        result = runner.invoke(rc_cli, ["-p", str(project)])
        assert result.exit_code == 0
        mock_review.assert_called_once()
        # Verify only guardian and sentinel agents
        call_kwargs = mock_review.call_args
        assert call_kwargs.kwargs["agents"] == ["guardian", "sentinel"]

    @patch("conclave.core.orchestrator.run_review", new_callable=AsyncMock)
    def test_dry_run_flag(self, mock_review, tmp_path):
        mock_review.return_value = 0
        project = tmp_path / "proj"
        project.mkdir()

        runner = CliRunner()
        result = runner.invoke(rc_cli, ["-p", str(project), "--dry-run"])
        assert mock_review.call_args.kwargs["dry_run"] is True


class TestCclCli:
    def test_requires_project_for_review(self):
        runner = CliRunner()
        result = runner.invoke(ccl_cli, [])
        # Should show error about missing project
        assert result.exit_code != 0 or "required" in (result.output or "").lower()

    @patch("conclave.core.orchestrator.run_review", new_callable=AsyncMock)
    def test_single_agent(self, mock_review, tmp_path):
        mock_review.return_value = 0
        project = tmp_path / "proj"
        project.mkdir()

        runner = CliRunner()
        result = runner.invoke(ccl_cli, ["-p", str(project), "-a", "guardian"])
        call_kwargs = mock_review.call_args
        assert call_kwargs.kwargs["agents"] == ["guardian"]

    @patch("conclave.core.orchestrator.run_review", new_callable=AsyncMock)
    def test_multiple_agents(self, mock_review, tmp_path):
        mock_review.return_value = 0
        project = tmp_path / "proj"
        project.mkdir()

        runner = CliRunner()
        result = runner.invoke(ccl_cli, ["-p", str(project), "--agents", "guardian,sentinel"])
        call_kwargs = mock_review.call_args
        assert call_kwargs.kwargs["agents"] == ["guardian", "sentinel"]

    @patch("conclave.core.orchestrator.initialize_project")
    def test_init_subcommand(self, mock_init, tmp_path):
        project = tmp_path / "proj"
        project.mkdir()

        runner = CliRunner()
        result = runner.invoke(ccl_cli, ["init", "-p", str(project)])
        assert result.exit_code == 0
        mock_init.assert_called_once()

    @patch("conclave.core.orchestrator.run_review", new_callable=AsyncMock)
    def test_ci_mode_exit_code(self, mock_review, tmp_path):
        mock_review.return_value = 1  # HOLD
        project = tmp_path / "proj"
        project.mkdir()

        runner = CliRunner()
        result = runner.invoke(ccl_cli, ["-p", str(project), "--ci"])
        # CI mode should propagate exit code
        assert result.exit_code == 1

    @patch("conclave.core.orchestrator.run_review", new_callable=AsyncMock)
    def test_output_format(self, mock_review, tmp_path):
        mock_review.return_value = 0
        project = tmp_path / "proj"
        project.mkdir()

        runner = CliRunner()
        result = runner.invoke(ccl_cli, ["-p", str(project), "-f", "junit"])
        assert mock_review.call_args.kwargs["output_format"] == "junit"
