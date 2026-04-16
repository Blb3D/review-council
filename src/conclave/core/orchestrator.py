"""Main review orchestrator.

Port of the Main function and Invoke-ReviewAgent from ccl.ps1.
"""

from __future__ import annotations

import asyncio
import os
import time
from datetime import datetime
from pathlib import Path
from typing import Optional

from rich.console import Console

from .. import __version__
from .agents import AGENT_DEFS, ALL_AGENT_KEYS, MOCK_FINDINGS, load_agent_instructions, load_contracts
from .config import get_effective_config, load_project_config
from .findings import export_findings_json, export_run_archive, parse_findings_markdown, remove_working_findings
from .calibration import build_calibration_context
from .licensing import check_feature, get_allowed_agents, get_current_tier
from .scanner import get_diff_context, get_project_file_tree, get_source_files_content
from .synthesis import calculate_verdict, generate_synthesis_report, get_exit_code
from .validator import run_validator
from ..formatters.junit import convert_parsed_findings_to_junit, export_junit_results
from ..providers.base import get_ai_provider

console = Console()


def initialize_project(project_path: Path) -> None:
    """Initialize .code-conclave directory structure in a project."""
    cc_dir = project_path / ".code-conclave"
    for subdir in ("reviews", "reviews/archive", "agents"):
        (cc_dir / subdir).mkdir(parents=True, exist_ok=True)

    config_path = cc_dir / "config.yaml"
    if not config_path.exists():
        config_path.write_text(
            "# Code Conclave project configuration\n"
            "# See docs/CONFIGURATION.md for full reference\n"
            "\n"
            f"conclave_version: \"{__version__}\"\n"
            "\n"
            "project:\n"
            f'  name: "{project_path.name}"\n'
            "\n"
            "ai:\n"
            "  provider: anthropic\n",
            encoding="utf-8",
        )

    console.print(f"  [green]Initialized[/green] .code-conclave/ in {project_path.name}")


def _parse_version(v: str) -> tuple[int, ...]:
    """Parse a version string like '3.0.0' into a tuple of ints."""
    try:
        return tuple(int(x) for x in v.split("."))
    except (ValueError, AttributeError):
        return (0, 0, 0)


def check_project_version(project_path: Path) -> None:
    """Check if the project's .code-conclave was created by a different version.

    Warns on mismatch and stamps the current version into config.
    """
    config = load_project_config(project_path)
    project_version = config.get("conclave_version", "")

    if not project_version:
        console.print(
            f"  [yellow]WARN[/yellow] No conclave_version in config "
            f"(created before v3.0.0). Stamping current version."
        )
        _stamp_version(project_path)
        return

    current = _parse_version(__version__)
    existing = _parse_version(project_version)

    if existing[0] < current[0]:
        # Major version bump — significant changes
        console.print(
            f"  [yellow]WARN[/yellow] Project config is v{project_version}, "
            f"running v{__version__} (major upgrade). "
            f"Review config for breaking changes."
        )
        _stamp_version(project_path)
    elif existing[:2] < current[:2]:
        # Minor version bump — new features available
        console.print(
            f"  [dim]INFO[/dim] Project config is v{project_version}, "
            f"running v{__version__}. Updating version stamp."
        )
        _stamp_version(project_path)
    elif existing > current:
        console.print(
            f"  [yellow]WARN[/yellow] Project config is v{project_version}, "
            f"but running older v{__version__}. "
            f"Some features may not be available."
        )
    # else: same version, no message needed


def _stamp_version(project_path: Path) -> None:
    """Write/update conclave_version in project config.yaml."""
    config_path = project_path / ".code-conclave" / "config.yaml"
    if not config_path.exists():
        return

    content = config_path.read_text(encoding="utf-8")
    # Strip BOM if present (could be at start or embedded from previous write)
    content = content.replace("\ufeff", "")

    import re
    if re.search(r"^conclave_version:", content, re.MULTILINE):
        content = re.sub(
            r"^conclave_version:.*$",
            f'conclave_version: "{__version__}"',
            content,
            count=1,
            flags=re.MULTILINE,
        )
    else:
        # Prepend after any leading comments
        lines = content.split("\n")
        insert_idx = 0
        for i, line in enumerate(lines):
            if line.startswith("#") or line.strip() == "":
                insert_idx = i + 1
            else:
                break
        lines.insert(insert_idx, f'conclave_version: "{__version__}"')
        lines.insert(insert_idx + 1, "")
        content = "\n".join(lines)

    config_path.write_text(content, encoding="utf-8")


async def run_review(
    project_path: Path,
    agents: Optional[list[str]] = None,
    output_format: str = "markdown",
    ci: bool = False,
    dry_run: bool = False,
    standard: Optional[str] = None,
    base_branch: Optional[str] = None,
    scan_depth: Optional[str] = None,
    ai_provider: Optional[str] = None,
    ai_model: Optional[str] = None,
    ai_endpoint: Optional[str] = None,
    timeout: int = 40,
    skip_synthesis: bool = False,
    skip_validation: bool = False,
    start_from: Optional[str] = None,
    profile: Optional[str] = None,
    add_standards: Optional[list[str]] = None,
    skip_standards: Optional[list[str]] = None,
) -> int:
    """Main review orchestrator. Returns exit code."""
    start_time = time.time()

    # Validate project path
    project_path = Path(project_path).resolve()
    if not project_path.exists():
        console.print(f"  [red]ERROR[/red] Project path does not exist: {project_path}")
        return 12

    # Auto-detect CI
    is_ci = ci or bool(
        os.environ.get("TF_BUILD")
        or os.environ.get("GITHUB_ACTIONS")
        or os.environ.get("CI")
        or os.environ.get("JENKINS_URL")
    )

    # Auto-init in CI/DryRun
    cc_dir = project_path / ".code-conclave"
    if not cc_dir.exists():
        if is_ci or dry_run:
            initialize_project(project_path)
        else:
            console.print("  [red]ERROR[/red] Project not initialized. Run: ccl init -p <path>")
            return 12

    # Version check
    check_project_version(project_path)

    reviews_dir = cc_dir / "reviews"
    reviews_dir.mkdir(parents=True, exist_ok=True)

    # Load config
    cli_overrides: dict = {}
    if ai_provider:
        cli_overrides.setdefault("ai", {})["provider"] = ai_provider
    if ai_model:
        provider_name = ai_provider or "anthropic"
        cli_overrides.setdefault("ai", {}).setdefault(provider_name, {})["model"] = ai_model

    effective_config = get_effective_config(
        project_path,
        profile=profile,
        add_standards=add_standards,
        skip_standards=skip_standards,
        cli_overrides=cli_overrides or None,
    )

    # Resolve agents
    allowed = get_allowed_agents()
    if agents:
        valid_agents = [a for a in agents if a in AGENT_DEFS and a in allowed]
    else:
        valid_agents = [a for a in ALL_AGENT_KEYS if a in allowed]

    if not valid_agents:
        console.print("  [red]ERROR[/red] No valid agents to run")
        return 11

    # Handle start_from
    if start_from and start_from in valid_agents:
        idx = valid_agents.index(start_from)
        valid_agents = valid_agents[idx:]

    project_name = effective_config.get("project", {}).get("name") or project_path.name

    # Banner
    console.print()
    console.print("  [bold cyan]CODE CONCLAVE[/bold cyan] v3.0.0")
    console.print(f"  Project: [white]{project_name}[/white]")
    console.print(f"  Agents:  [white]{', '.join(a.upper() for a in valid_agents)}[/white]")
    tier = get_current_tier()
    console.print(f"  Tier:    [white]{tier.value.upper()}[/white]")
    if dry_run:
        console.print("  Mode:    [yellow]DRY RUN[/yellow]")
    console.print()

    # Auto-detect scan depth
    if not scan_depth:
        scan_depth = "light" if is_ci else "standard"

    # Build shared context
    console.print("  [cyan]Scanning project...[/cyan]")

    file_tree = get_project_file_tree(project_path)
    contracts_text = load_contracts(project_path)

    diff_context = None
    source_content = ""

    if scan_depth == "light":
        diff_context = get_diff_context(project_path, base_branch=base_branch)
        if diff_context:
            source_content = diff_context.file_contents
            console.print(
                f"  [green]OK[/green] Diff scan: {diff_context.file_count} changed files "
                f"({diff_context.total_size_kb} KB)"
            )
        else:
            scan_depth = "standard"

    if scan_depth in ("standard", "deep"):
        max_kb = effective_config.get("ai", {}).get("max_context_kb", 100)
        scan_result = get_source_files_content(project_path, max_size_kb=max_kb)
        source_content = scan_result.content
        console.print(
            f"  [green]OK[/green] Tier scan: {scan_result.file_count}/{scan_result.total_eligible} "
            f"files ({scan_result.total_size_kb} KB)"
        )

    # Build SharedContext (cacheable across agents)
    shared_parts = [
        "# CONTRACTS\n\n" + contracts_text,
        "\n\n# PROJECT FILE STRUCTURE\n\n" + file_tree,
        "\n\n# SOURCE FILES\n\n" + source_content,
    ]
    if diff_context and diff_context.diff:
        shared_parts.append("\n\n# GIT DIFF\n\n" + diff_context.diff)

    shared_context = "".join(shared_parts)

    # Context summary footer
    total_eligible = 0
    file_count = 0
    if diff_context:
        file_count = diff_context.file_count
    elif source_content:
        # Rough count from content
        file_count = source_content.count("## File:")
    shared_context += (
        f"\n\n---\n"
        f"CONTEXT SUMMARY: You have been provided {file_count} source files. "
        f"Do NOT assume the contents of files not shown above. "
        f"If a file appears in FILE STRUCTURE but NOT in SOURCE FILES, "
        f"cap severity at MEDIUM and note it is unverified."
    )

    # Initialize provider
    provider = None
    if not dry_run:
        try:
            provider_name = effective_config.get("ai", {}).get("provider", "anthropic")
            provider = get_ai_provider(
                effective_config,
                provider_override=ai_provider,
                model_override=ai_model,
                endpoint_override=ai_endpoint,
            )
            console.print(f"  [green]OK[/green] Provider: {provider.name}")
        except Exception as e:
            console.print(f"  [red]ERROR[/red] Failed to initialize AI provider: {e}")
            return 13

    # Clean previous working findings
    remove_working_findings(reviews_dir)

    # Run agents
    all_findings: dict[str, dict] = {}
    run_timestamp = datetime.now().strftime("%Y-%m-%dT%H:%M:%S")

    for agent_key in valid_agents:
        agent_def = AGENT_DEFS[agent_key]
        color = agent_def.get("color", "white")
        console.print(f"\n  [{color}]Running {agent_def['name']}...[/{color}]")

        agent_start = time.time()

        if dry_run:
            # Use mock findings
            raw_markdown = MOCK_FINDINGS.get(agent_key, f"# {agent_key.upper()} Review\n\nNo findings.\n\nCOMPLETE: 0 BLOCKER, 0 HIGH, 0 MEDIUM, 0 LOW\n")
        else:
            # Load agent instructions and call AI
            agent_instructions = load_agent_instructions(agent_key, project_path)
            agent_tier = (
                effective_config.get("agents", {})
                .get(agent_key, {})
                .get("tier", "primary")
            )

            # Build calibration context for this agent
            cal_context = build_calibration_context(project_path, agent_key)

            system_prompt = (
                f"You are {agent_def['name']}, the {agent_def['role']} specialist.\n\n"
                f"{agent_instructions}"
            )
            if cal_context:
                system_prompt += f"\n\n{cal_context}"

            user_prompt = (
                f"Review this project and provide findings in the exact format "
                f"specified in CONTRACTS.\n\n"
                f"End with: COMPLETE: X BLOCKER, Y HIGH, Z MEDIUM, W LOW"
            )

            # Use prompt caching if available
            use_caching = check_feature("prompt_caching")
            sc = shared_context if use_caching else None
            sp = system_prompt if use_caching else shared_context + "\n\n" + system_prompt

            result = await provider.complete_with_retry(
                shared_context=sc,
                system_prompt=sp,
                user_prompt=user_prompt,
                tier=agent_tier,
            )

            if not result.success:
                console.print(f"  [red]FAILED[/red] {agent_def['name']}: {result.error}")
                all_findings[agent_key] = {
                    "agent": {"id": agent_key, "name": agent_def["name"], "role": agent_def["role"], "tier": agent_tier},
                    "status": "error",
                    "summary": {"blockers": 0, "high": 0, "medium": 0, "low": 0, "total": 0},
                    "findings": [],
                    "run": {"durationSeconds": round(time.time() - agent_start, 2)},
                    "error": result.error,
                }
                continue

            raw_markdown = result.content or ""

        agent_duration = time.time() - agent_start

        # Parse findings
        tokens = None
        if not dry_run and result and result.tokens_used:
            tokens = result.tokens_used

        parsed = parse_findings_markdown(
            content=raw_markdown,
            agent_key=agent_key,
            agent_name=agent_def["name"],
            agent_role=agent_def["role"],
            run_timestamp=run_timestamp,
            project_name=project_name,
            project_path=str(project_path),
            duration_seconds=agent_duration,
            tokens_used=tokens,
            tier=effective_config.get("agents", {}).get(agent_key, {}).get("tier", "primary"),
            dry_run=dry_run,
        )

        all_findings[agent_key] = parsed

        # Save findings files
        md_path = reviews_dir / f"{agent_key}-findings.md"
        md_path.write_text(raw_markdown, encoding="utf-8")

        json_path = reviews_dir / f"{agent_key}-findings.json"
        export_findings_json(parsed, json_path)

        # Report
        s = parsed.get("summary", {})
        console.print(
            f"  [green]OK[/green] {agent_def['name']}: "
            f"{s.get('total', 0)} findings "
            f"({s.get('blockers', 0)}B/{s.get('high', 0)}H/{s.get('medium', 0)}M/{s.get('low', 0)}L) "
            f"in {round(agent_duration, 1)}s"
        )

    # Validation step: stress-test BLOCKER/HIGH findings
    if not skip_validation and len(all_findings) > 0 and provider is not None:
        all_findings, validation_stats = await run_validator(
            all_findings=all_findings,
            shared_context=shared_context,
            project_path=project_path,
            provider=provider,
            effective_config=effective_config,
            dry_run=dry_run,
        )
        # Re-export adjusted findings
        if validation_stats.get("downgraded", 0) > 0 or validation_stats.get("rejected", 0) > 0:
            for agent_key in all_findings:
                json_path = reviews_dir / f"{agent_key}-findings.json"
                export_findings_json(all_findings[agent_key], json_path)

    # Synthesis
    if not skip_synthesis and len(all_findings) > 0:
        console.print("\n  [cyan]Generating synthesis report...[/cyan]")
        verdict = calculate_verdict(all_findings)
        exit_code = get_exit_code(verdict)

        total_duration = time.time() - start_time
        provider_name = effective_config.get("ai", {}).get("provider", "unknown")

        report = generate_synthesis_report(
            all_findings,
            project_name=project_name,
            project_path=str(project_path),
            duration_seconds=total_duration,
            provider=provider_name if not dry_run else "dry-run",
            standard=standard,
            dry_run=dry_run,
        )

        report_path = reviews_dir / "RELEASE-READINESS-REPORT.md"
        report_path.write_text(report, encoding="utf-8")

        # JUnit XML
        if output_format == "junit" or is_ci:
            junit_findings = convert_parsed_findings_to_junit(all_findings)
            junit_path = reviews_dir / "conclave-results.xml"
            junit_result = export_junit_results(
                junit_findings, junit_path, project_name=project_name, duration=total_duration
            )
            console.print(
                f"  [green]OK[/green] JUnit XML: {junit_result['total_tests']} tests, "
                f"{junit_result['failures']} failures"
            )

        # Archive
        export_run_archive(
            reviews_dir,
            all_findings,
            {
                "timestamp": datetime.now(),
                "project": project_name,
                "project_path": str(project_path),
                "duration": total_duration,
                "dry_run": dry_run,
                "base_branch": base_branch,
                "standard": standard,
                "provider": provider_name if not dry_run else "dry-run",
                "agents_requested": valid_agents,
                "verdict": verdict.value,
                "exit_code": exit_code,
            },
        )

        # Verdict display
        verdict_colors = {"SHIP": "green", "CONDITIONAL": "yellow", "HOLD": "red"}
        color = verdict_colors.get(verdict.value, "white")
        console.print(f"\n  [{color}]Verdict: {verdict.value}[/{color}]")
        console.print(f"  Results: {reviews_dir}")
        console.print()

        if is_ci:
            console.print(f"  CI Mode: Exiting with code {exit_code}")

        return exit_code

    return 0
