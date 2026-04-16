"""Code Conclave (ccl) - Full 6-agent AI code review.

PRO+ tier entry point: all 6 agents + compliance mapping.
"""

from __future__ import annotations

import asyncio
import sys
from pathlib import Path

import click


@click.group(invoke_without_command=True)
@click.pass_context
@click.option("--project", "-p", type=click.Path(exists=True), help="Project path")
@click.option("--output-format", "-f", type=click.Choice(["markdown", "json", "junit"]), default="markdown")
@click.option("--ci", is_flag=True, help="CI mode: enable exit codes")
@click.option("--dry-run", is_flag=True, help="Use mock findings (no API calls)")
@click.option("--timeout", type=int, default=40)
@click.option("--ai-provider", type=click.Choice(["anthropic", "azure-openai", "openai", "ollama"]))
@click.option("--ai-model", type=str, help="Model override")
@click.option("--ai-endpoint", type=str, help="Endpoint override")
@click.option("--base-branch", type=str, help="Base branch for diff-scoping")
@click.option("--scan-depth", type=click.Choice(["light", "standard", "deep"]))
@click.option("--agent", "-a", type=str, help="Run a single agent")
@click.option("--agents", type=str, help="Comma-separated agents to run")
@click.option("--start-from", type=str, help="Resume from a specific agent")
@click.option("--skip-synthesis", is_flag=True)
@click.option("--skip-validation", is_flag=True, help="Skip the validator step")
@click.option("--standard", "-s", type=str, help="Compliance standard ID")
@click.option("--profile", type=str, help="Compliance profile name")
@click.option("--add-standards", type=str, help="Comma-separated standards to add")
@click.option("--skip-standards", type=str, help="Comma-separated standards to skip")
def ccl_cli(
    ctx: click.Context,
    project: str | None,
    output_format: str,
    ci: bool,
    dry_run: bool,
    timeout: int,
    ai_provider: str | None,
    ai_model: str | None,
    ai_endpoint: str | None,
    base_branch: str | None,
    scan_depth: str | None,
    agent: str | None,
    agents: str | None,
    start_from: str | None,
    skip_synthesis: bool,
    skip_validation: bool,
    standard: str | None,
    profile: str | None,
    add_standards: str | None,
    skip_standards: str | None,
) -> None:
    """Code Conclave - Full 6-agent AI code review with compliance mapping."""
    if ctx.invoked_subcommand is not None:
        return

    if not project:
        click.echo("Error: --project/-p is required for review mode.", err=True)
        ctx.exit(11)
        return

    from ..core.orchestrator import run_review

    agent_list = None
    if agent:
        agent_list = [agent.lower()]
    elif agents:
        agent_list = [a.strip().lower() for a in agents.split(",")]

    exit_code = asyncio.run(
        run_review(
            project_path=Path(project),
            agents=agent_list,
            output_format=output_format,
            ci=ci,
            dry_run=dry_run,
            standard=standard,
            timeout=timeout,
            ai_provider=ai_provider,
            ai_model=ai_model,
            ai_endpoint=ai_endpoint,
            base_branch=base_branch,
            scan_depth=scan_depth,
            skip_synthesis=skip_synthesis,
            skip_validation=skip_validation,
            start_from=start_from,
            profile=profile,
            add_standards=[s.strip() for s in add_standards.split(",")] if add_standards else None,
            skip_standards=[s.strip() for s in skip_standards.split(",")] if skip_standards else None,
        )
    )
    if ci:
        sys.exit(exit_code)


@ccl_cli.command()
@click.option("--project", "-p", type=click.Path(exists=True), required=True)
def init(project: str) -> None:
    """Initialize Code Conclave in a project."""
    from ..core.orchestrator import initialize_project

    initialize_project(Path(project))


@ccl_cli.command()
@click.option("--project", "-p", type=click.Path(exists=True), required=True)
@click.argument("finding_id")
@click.option("--reason", "-r", required=True, help="Why this is a false positive")
def reject(project: str, finding_id: str, reason: str) -> None:
    """Mark a finding as a false positive for future runs.

    Example: ccl reject GUARDIAN-002 -p ./repo -r "Admin-only endpoint, parameterized ORM"
    """
    from ..core.calibration import add_reviewed_finding
    from ..core.findings import _load_latest_findings

    project_path = Path(project)
    finding = _load_latest_findings(project_path, finding_id)

    entry = add_reviewed_finding(
        project_path=project_path,
        finding_id=finding_id,
        agent=finding.get("agent", finding_id.split("-")[0].lower()) if finding else finding_id.split("-")[0].lower(),
        original_severity=finding.get("severity", "UNKNOWN") if finding else "UNKNOWN",
        adjusted_severity="REJECTED",
        verdict="false_positive",
        reason=reason,
        file_path=finding.get("file") if finding else None,
        title=finding.get("title") if finding else None,
    )
    click.echo(f"Rejected {finding_id}: {reason}")
    click.echo(f"Saved to .code-conclave/calibration.yaml")


@ccl_cli.command()
@click.option("--project", "-p", type=click.Path(exists=True), required=True)
@click.argument("finding_id")
@click.option("--severity", "-s", required=True, type=click.Choice(["BLOCKER", "HIGH", "MEDIUM", "LOW"]))
@click.option("--reason", "-r", required=True, help="Why the severity should change")
def adjust(project: str, finding_id: str, severity: str, reason: str) -> None:
    """Adjust a finding's severity for future runs.

    Example: ccl adjust GUARDIAN-002 -p ./repo -s LOW -r "Admin endpoint, already has read access"
    """
    from ..core.calibration import add_reviewed_finding
    from ..core.findings import _load_latest_findings

    project_path = Path(project)
    finding = _load_latest_findings(project_path, finding_id)

    entry = add_reviewed_finding(
        project_path=project_path,
        finding_id=finding_id,
        agent=finding.get("agent", finding_id.split("-")[0].lower()) if finding else finding_id.split("-")[0].lower(),
        original_severity=finding.get("severity", "UNKNOWN") if finding else "UNKNOWN",
        adjusted_severity=severity,
        verdict="adjusted",
        reason=reason,
        file_path=finding.get("file") if finding else None,
        title=finding.get("title") if finding else None,
    )
    click.echo(f"Adjusted {finding_id} to {severity}: {reason}")
    click.echo(f"Saved to .code-conclave/calibration.yaml")


@ccl_cli.command()
@click.option("--project", "-p", type=click.Path(exists=True), required=True)
@click.argument("finding_id")
def confirm(project: str, finding_id: str) -> None:
    """Confirm a finding as a true positive (good catch).

    Example: ccl confirm GUARDIAN-001 -p ./repo
    """
    from ..core.calibration import add_reviewed_finding
    from ..core.findings import _load_latest_findings

    project_path = Path(project)
    finding = _load_latest_findings(project_path, finding_id)

    entry = add_reviewed_finding(
        project_path=project_path,
        finding_id=finding_id,
        agent=finding.get("agent", finding_id.split("-")[0].lower()) if finding else finding_id.split("-")[0].lower(),
        original_severity=finding.get("severity", "UNKNOWN") if finding else "UNKNOWN",
        adjusted_severity=finding.get("severity", "UNKNOWN") if finding else "UNKNOWN",
        verdict="confirmed",
        reason="Confirmed by human reviewer",
        file_path=finding.get("file") if finding else None,
        title=finding.get("title") if finding else None,
    )
    click.echo(f"Confirmed {finding_id} as true positive")
    click.echo(f"Saved to .code-conclave/calibration.yaml")


@ccl_cli.command("add-rule")
@click.option("--project", "-p", type=click.Path(exists=True), required=True)
@click.argument("rule")
@click.option("--agent", "-a", default="all", help="Agent this applies to (default: all)")
@click.option("--severity-cap", type=click.Choice(["BLOCKER", "HIGH", "MEDIUM", "LOW"]))
def add_rule(project: str, rule: str, agent: str, severity_cap: str | None) -> None:
    """Add a project-specific rule for future reviews.

    Example: ccl add-rule "All /api/v1/admin/ endpoints are behind JWT auth" -p ./repo -a guardian
    """
    from ..core.calibration import add_project_rule

    entry = add_project_rule(
        project_path=Path(project),
        rule=rule,
        applies_to=agent.lower(),
        severity_cap=severity_cap,
    )
    click.echo(f"Added rule: {rule}")
    if severity_cap:
        click.echo(f"  Severity cap: {severity_cap} for {agent}")
    click.echo(f"Saved to .code-conclave/calibration.yaml")


def main() -> None:
    ccl_cli()


if __name__ == "__main__":
    main()
