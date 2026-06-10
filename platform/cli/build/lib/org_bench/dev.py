"""
org-bench dev — local development workflow commands.

  setup      Initialise folder structure and .env file
  start      Spin up the local Docker Compose stack
  stop       Stop the local stack (preserve data volumes)
  new-app    Scaffold a new Frappe app inside the running container
"""

import os
import shutil
import subprocess
import sys
from pathlib import Path

import click
from dotenv import load_dotenv
from rich.console import Console

console = Console()

# Resolve platform/ directory relative to this file (platform/cli/org_bench/)
# Resolve platform/ from cwd (where the developer runs org-bench), with an
# escape hatch via ORG_BENCH_PLATFORM_DIR for non-standard setups.
# __file__-relative paths break when installed via pipx/uv tool.
PLATFORM_DIR = Path(os.environ.get("ORG_BENCH_PLATFORM_DIR", "")).resolve() \
    if os.environ.get("ORG_BENCH_PLATFORM_DIR") \
    else (Path.cwd() / "platform").resolve()
COMPOSE_FILE = PLATFORM_DIR / "docker-compose.dev.yml"
ENV_EXAMPLE = PLATFORM_DIR / ".env.example"
ENV_FILE = PLATFORM_DIR / ".env"
APPS_DIR = PLATFORM_DIR / "apps"


def _load_env() -> None:
    """Load platform/.env into the current process environment."""
    if ENV_FILE.exists():
        load_dotenv(ENV_FILE, override=True)


def _run(cmd: list[str], **kwargs) -> subprocess.CompletedProcess:
    """Run a subprocess, streaming output to the terminal."""
    console.print(f"[dim]$ {' '.join(cmd)}[/dim]")
    return subprocess.run(cmd, check=True, **kwargs)


@click.group()
def dev() -> None:
    """Local development environment commands."""


@dev.command()
def setup() -> None:
    """
    Initialise a clean local folder structure.

    - Creates platform/.env from .env.example if it does not exist
    - Creates platform/apps/ directory for bind-mounted app code
    - Pulls base Docker images
    """
    console.rule("[bold blue]org-bench dev setup[/bold blue]")

    # --- .env ---
    if ENV_FILE.exists():
        console.print(f"[yellow].env already exists at {ENV_FILE} — skipping.[/yellow]")
    else:
        shutil.copy(ENV_EXAMPLE, ENV_FILE)
        console.print(f"[green]Created {ENV_FILE}[/green]")
        console.print("[bold yellow]⚠  Edit platform/.env before starting the stack.[/bold yellow]")

    # --- apps/ directory ---
    APPS_DIR.mkdir(exist_ok=True)
    console.print(f"[green]apps/ directory ready: {APPS_DIR}[/green]")

    # --- Pull images ---
    _load_env()
    console.print("[blue]Pulling base images...[/blue]")
    _run([
        "docker", "compose",
        "-f", str(COMPOSE_FILE),
        "--env-file", str(ENV_FILE),
        "pull",
        "--ignore-pull-failures",
        "mariadb", "redis-cache", "redis-queue", "redis-socketio", "traefik",
    ])

    console.print("[bold green]✓ Setup complete. Run `org-bench dev start` to launch.[/bold green]")
    console.print()
    console.print("[dim]Install org-bench (if not already):[/dim]")
    console.print("[dim]  pipx install platform/cli          # recommended[/dim]")
    console.print("[dim]  uv tool install platform/cli       # if using uv[/dim]")


@dev.command()
def start() -> None:
    """
    Start the local Docker Compose stack.

    On first run, the bootstrap service creates the Frappe site and installs
    all apps from apps.json. Subsequent runs skip initialisation.
    """
    console.rule("[bold blue]org-bench dev start[/bold blue]")
    _load_env()

    if not ENV_FILE.exists():
        console.print("[red]platform/.env not found. Run `org-bench dev setup` first.[/red]")
        sys.exit(1)

    _run([
        "docker", "compose",
        "-f", str(COMPOSE_FILE),
        "--env-file", str(ENV_FILE),
        "up", "--build", "--detach",
    ])

    site = os.environ.get("FRAPPE_SITE_NAME", "dev.localhost")
    console.print(f"[bold green]✓ Stack is up.[/bold green]")
    console.print(f"  Web:       http://{site}")
    console.print(f"  Traefik:   http://localhost:8082")
    console.print(f"  Logs:      docker compose -f platform/docker-compose.dev.yml logs -f")


@dev.command()
def stop() -> None:
    """Stop the local stack. Data volumes are preserved."""
    console.rule("[bold blue]org-bench dev stop[/bold blue]")
    _load_env()
    _run([
        "docker", "compose",
        "-f", str(COMPOSE_FILE),
        "--env-file", str(ENV_FILE),
        "down",
    ])
    console.print("[green]Stack stopped. Data volumes preserved.[/green]")


@dev.command("new-app")
@click.argument("app_name")
def new_app(app_name: str) -> None:
    """
    Scaffold a new Frappe app inside the running frappe-web container.

    The app is created inside the bind-mounted apps/ directory so files
    appear on your host machine immediately after creation.

    APP_NAME must be a valid Python identifier (snake_case recommended).
    """
    console.rule(f"[bold blue]org-bench dev new-app {app_name}[/bold blue]")
    _load_env()

    console.print(f"[blue]Scaffolding app '{app_name}' inside container...[/blue]")

    _run([
        "docker", "compose",
        "-f", str(COMPOSE_FILE),
        "--env-file", str(ENV_FILE),
        "exec", "frappe-web",
        "bash", "-c",
        f"cd /home/frappe/frappe-bench && bench new-app {app_name}",
    ])

    console.print(f"[bold green]✓ App '{app_name}' created at platform/apps/{app_name}[/bold green]")
    console.print(f"  Add it to platform/apps.json to include it in production builds.")
