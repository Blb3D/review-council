"""Review Council (rc) - Lightweight 2-agent PR check.

FREE tier entry point: runs guardian + sentinel only.
"""

from __future__ import annotations

import asyncio
import sys
from pathlib import Path

import click


@click.command(name="rc")
@click.option("--project", "-p", type=click.Path(exists=True), required=True, help="Project path")
@click.option("--output-format", "-f", type=click.Choice(["markdown", "json", "junit"]), default="markdown")
@click.option("--ci", is_flag=True, help="CI mode: enable exit codes")
@click.option("--dry-run", is_flag=True, help="Use mock findings (no API calls)")
@click.option("--timeout", type=int, default=40)
@click.option("--ai-provider", type=click.Choice(["anthropic", "azure-openai", "openai", "ollama"]))
@click.option("--ai-model", type=str, help="Model override")
@click.option("--ai-endpoint", type=str, help="Endpoint override")
@click.option("--base-branch", type=str, help="Base branch for diff-scoping")
@click.option("--scan-depth", type=click.Choice(["light", "standard", "deep"]))
def rc_cli(
    project: str,
    output_format: str,
    ci: bool,
    dry_run: bool,
    timeout: int,
    ai_provider: str | None,
    ai_model: str | None,
    ai_endpoint: str | None,
    base_branch: str | None,
    scan_depth: str | None,
) -> None:
    """Review Council - Quick 2-agent PR check (guardian + sentinel)."""
    from ..core.orchestrator import run_review

    exit_code = asyncio.run(
        run_review(
            project_path=Path(project),
            agents=["guardian", "sentinel"],
            output_format=output_format,
            ci=ci,
            dry_run=dry_run,
            timeout=timeout,
            ai_provider=ai_provider,
            ai_model=ai_model,
            ai_endpoint=ai_endpoint,
            base_branch=base_branch,
            scan_depth=scan_depth,
        )
    )
    if ci:
        sys.exit(exit_code)


def main() -> None:
    rc_cli()


if __name__ == "__main__":
    main()
