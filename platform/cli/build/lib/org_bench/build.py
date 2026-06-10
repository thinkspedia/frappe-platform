"""
org-bench build — build and tag the production Docker image.

  build --tag <version>   Build production stage, tag, and optionally push.

The GITHUB_TOKEN environment variable is passed as a BuildKit secret so
private app repos can be cloned without the token being baked into any layer.
"""

import os
import subprocess
import sys
from pathlib import Path

import click
from dotenv import load_dotenv
from rich.console import Console

console = Console()

PLATFORM_DIR = Path(os.environ.get("ORG_BENCH_PLATFORM_DIR", "")).resolve() \
    if os.environ.get("ORG_BENCH_PLATFORM_DIR") \
    else (Path.cwd() / "platform").resolve()
ENV_FILE = PLATFORM_DIR / ".env"
DOCKERFILE = PLATFORM_DIR / "Dockerfile"


def _load_env() -> None:
    if ENV_FILE.exists():
        load_dotenv(ENV_FILE, override=True)


def _run(cmd: list[str], **kwargs) -> subprocess.CompletedProcess:
    console.print(f"[dim]$ {' '.join(cmd)}[/dim]")
    return subprocess.run(cmd, check=True, **kwargs)


@click.command()
@click.option("--tag", required=True, help="Image tag (e.g. v1.2.0 or git SHA)")
@click.option("--push", is_flag=True, default=False, help="Push image to registry after build")
@click.option(
    "--platform",
    default="linux/amd64",
    show_default=True,
    help="Target platform(s), e.g. linux/amd64,linux/arm64",
)
def build(tag: str, push: bool, platform: str) -> None:
    """
    Build the production Docker image and tag it.

    Requires GITHUB_TOKEN in the environment for private app repos.
    The token is passed as a BuildKit secret and never baked into the image.

    Examples:
      org-bench build --tag v1.0.0
      org-bench build --tag v1.0.0 --push
      org-bench build --tag latest --platform linux/amd64,linux/arm64 --push
    """
    console.rule(f"[bold blue]org-bench build --tag {tag}[/bold blue]")
    _load_env()

    registry = os.environ.get("IMAGE_REGISTRY", "ghcr.io/thinkspedia")
    name = os.environ.get("IMAGE_NAME", "frappe-platform")
    full_tag = f"{registry}/{name}:{tag}"

    github_token = os.environ.get("GITHUB_TOKEN", "")
    if not github_token:
        console.print(
            "[yellow]⚠  GITHUB_TOKEN not set. Private repos in apps.json may fail.[/yellow]"
        )

    build_args = [
        f"PYTHON_VERSION={os.environ.get('PYTHON_VERSION', '3.11')}",
        f"NODE_VERSION={os.environ.get('NODE_VERSION', '18.20.4')}",
        f"FRAPPE_VERSION={os.environ.get('FRAPPE_VERSION', 'version-15')}",
        f"FRAPPE_REPO={os.environ.get('FRAPPE_REPO', 'https://github.com/frappe/frappe')}",
    ]

    cmd = [
        "docker", "buildx", "build",
        "--file", str(DOCKERFILE),
        "--target", "production",
        "--tag", full_tag,
        "--platform", platform,
        # Pass GITHUB_TOKEN as a BuildKit secret — never written to a layer
        "--secret", f"id=github_token,env=GITHUB_TOKEN",
        # Build context is platform/
        str(PLATFORM_DIR),
    ]

    for arg in build_args:
        cmd += ["--build-arg", arg]

    if push:
        cmd.append("--push")
    else:
        cmd.append("--load")

    env = os.environ.copy()
    env["GITHUB_TOKEN"] = github_token
    env["DOCKER_BUILDKIT"] = "1"

    console.print(f"[blue]Building image: {full_tag}[/blue]")
    result = subprocess.run(cmd, env=env)

    if result.returncode != 0:
        console.print(f"[red]Build failed (exit {result.returncode})[/red]")
        sys.exit(result.returncode)

    console.print(f"[bold green]✓ Image built: {full_tag}[/bold green]")
    if push:
        console.print(f"  Pushed to registry.")
    else:
        console.print(f"  Loaded locally. Use --push to push to registry.")
