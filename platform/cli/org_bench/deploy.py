"""
org-bench deploy — deploy to Nomad or Dokploy.

  deploy --env prod --tag v1.0.0      Deploy to production Nomad cluster
  deploy --env staging --tag v1.0.0   Deploy to staging Nomad cluster
  deploy --mode dokploy --env prod --tag v1.0.0  Deploy via Dokploy API

Deploy modes (set NOMAD_DEPLOY_MODE in .env or pass --mode):
  pull  — runs `nomad job run` on the Nomad server (SSH into server first)
  ship  — runs `nomad job run` from the local machine using NOMAD_ADDR + NOMAD_TOKEN
  dokploy — triggers a Dokploy deployment via its REST API
"""

import os
import subprocess
import sys
import time
from pathlib import Path

import click
import requests
from dotenv import load_dotenv
from rich.console import Console

console = Console()

PLATFORM_DIR = Path(__file__).resolve().parents[2]
ENV_FILE = PLATFORM_DIR / ".env"
NOMAD_JOB_FILE = PLATFORM_DIR / "nomad" / "frappe.nomad.hcl"
DOKPLOY_FILE = PLATFORM_DIR / "dokploy" / "dokploy.yml"


def _load_env() -> None:
    if ENV_FILE.exists():
        load_dotenv(ENV_FILE, override=True)


def _run(cmd: list[str], **kwargs) -> subprocess.CompletedProcess:
    console.print(f"[dim]$ {' '.join(cmd)}[/dim]")
    return subprocess.run(cmd, check=True, **kwargs)


@click.command()
@click.option(
    "--env",
    "environment",
    required=True,
    type=click.Choice(["prod", "staging"]),
    help="Target environment",
)
@click.option("--tag", required=True, help="Image tag to deploy (e.g. v1.0.0)")
@click.option(
    "--mode",
    type=click.Choice(["pull", "ship", "dokploy"]),
    default=None,
    help="Deploy mode (overrides NOMAD_DEPLOY_MODE from .env)",
)
@click.option(
    "--web-count",
    type=int,
    default=None,
    help="Override number of Gunicorn web instances",
)
@click.option(
    "--worker-count",
    type=int,
    default=None,
    help="Override number of Celery worker instances",
)
@click.option(
    "--dry-run",
    is_flag=True,
    default=False,
    help="Print the Nomad job plan without deploying",
)
def deploy(
    environment: str,
    tag: str,
    mode: str | None,
    web_count: int | None,
    worker_count: int | None,
    dry_run: bool,
) -> None:
    """
    Deploy the Frappe platform to production or staging.

    Examples:
      org-bench deploy --env prod --tag v1.0.0
      org-bench deploy --env staging --tag v1.0.0 --web-count 4
      org-bench deploy --env prod --tag v1.0.0 --dry-run
      org-bench deploy --env prod --tag v1.0.0 --mode dokploy
    """
    console.rule(f"[bold blue]org-bench deploy --env {environment} --tag {tag}[/bold blue]")
    _load_env()

    registry = os.environ.get("IMAGE_REGISTRY", "ghcr.io/thinkspedia")
    image_name = os.environ.get("IMAGE_NAME", "frappe-platform")
    full_image = f"{registry}/{image_name}:{tag}"

    deploy_mode = mode or os.environ.get("NOMAD_DEPLOY_MODE", "ship")

    console.print(f"  Environment : {environment}")
    console.print(f"  Image       : {full_image}")
    console.print(f"  Mode        : {deploy_mode}")

    if deploy_mode == "dokploy":
        _deploy_dokploy(environment, full_image, tag)
    elif deploy_mode in ("pull", "ship"):
        _deploy_nomad(environment, full_image, web_count, worker_count, dry_run)
    else:
        console.print(f"[red]Unknown deploy mode: {deploy_mode}[/red]")
        sys.exit(1)


# ---------------------------------------------------------------------------
# Nomad deployment
# ---------------------------------------------------------------------------

def _deploy_nomad(
    environment: str,
    image: str,
    web_count: int | None,
    worker_count: int | None,
    dry_run: bool,
) -> None:
    nomad_addr = os.environ.get("NOMAD_ADDR", "http://localhost:4646")
    nomad_token = os.environ.get("NOMAD_TOKEN", "")
    site_name = os.environ.get("FRAPPE_SITE_NAME", "erp.example.com")
    host_name = os.environ.get("HOST_NAME", site_name)

    env = os.environ.copy()
    env["NOMAD_ADDR"] = nomad_addr
    if nomad_token:
        env["NOMAD_TOKEN"] = nomad_token

    # Build -var flags
    vars_: list[str] = [
        f'image={image}',
        f'site_name={site_name}',
        f'host_name={host_name}',
        f'db_host={os.environ.get("DB_HOST", "mariadb.service.consul")}',
        f'db_port={os.environ.get("DB_PORT", "3306")}',
        f'db_password={os.environ.get("DB_PASSWORD", "")}',
        f'redis_cache={os.environ.get("REDIS_CACHE", "redis-cache.service.consul:6379")}',
        f'redis_queue={os.environ.get("REDIS_QUEUE", "redis-queue.service.consul:6379")}',
        f'redis_socketio={os.environ.get("REDIS_SOCKETIO", "redis-socketio.service.consul:6379")}',
    ]
    if web_count is not None:
        vars_.append(f"web_count={web_count}")
    if worker_count is not None:
        vars_.append(f"worker_count={worker_count}")

    var_flags: list[str] = []
    for v in vars_:
        var_flags += ["-var", v]

    if dry_run:
        console.print("[yellow]Dry-run: running `nomad job plan`...[/yellow]")
        cmd = ["nomad", "job", "plan"] + var_flags + [str(NOMAD_JOB_FILE)]
        subprocess.run(cmd, env=env)
        return

    # Run the job
    cmd = ["nomad", "job", "run"] + var_flags + [str(NOMAD_JOB_FILE)]
    console.print(f"[blue]Submitting job to Nomad ({nomad_addr})...[/blue]")
    result = subprocess.run(cmd, env=env, capture_output=True, text=True)

    if result.returncode != 0:
        console.print(f"[red]Nomad job submission failed:[/red]\n{result.stderr}")
        sys.exit(1)

    console.print(result.stdout)

    # Poll deployment status
    _poll_nomad_deployment(env)


def _poll_nomad_deployment(env: dict) -> None:
    """Poll `nomad job status frappe` until the deployment is healthy or failed."""
    console.print("[blue]Polling deployment status...[/blue]")
    for attempt in range(30):
        time.sleep(10)
        result = subprocess.run(
            ["nomad", "job", "status", "-short", "frappe"],
            env=env,
            capture_output=True,
            text=True,
        )
        output = result.stdout + result.stderr
        if "running" in output.lower() and "failed" not in output.lower():
            console.print(f"[bold green]✓ Deployment healthy after {(attempt + 1) * 10}s[/bold green]")
            return
        if "failed" in output.lower() or "dead" in output.lower():
            console.print(f"[red]✗ Deployment failed. Check `nomad job status frappe`.[/red]")
            sys.exit(1)
        console.print(f"  [{attempt + 1}/30] Waiting... ({output.strip().splitlines()[-1] if output.strip() else 'pending'})")

    console.print("[yellow]⚠  Timed out waiting for healthy deployment. Check Nomad UI.[/yellow]")


# ---------------------------------------------------------------------------
# Dokploy deployment
# ---------------------------------------------------------------------------

def _deploy_dokploy(environment: str, image: str, tag: str) -> None:
    server = os.environ.get("DOKPLOY_SERVER", "")
    token = os.environ.get("DOKPLOY_TOKEN", "")

    if not server or not token:
        console.print("[red]DOKPLOY_SERVER and DOKPLOY_TOKEN must be set in platform/.env[/red]")
        sys.exit(1)

    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
    }

    # Dokploy v1 API: trigger a redeploy with a new image tag
    # Adjust endpoint to match your Dokploy version's API schema.
    payload = {
        "image": image,
        "tag": tag,
        "environment": environment,
    }

    console.print(f"[blue]Triggering Dokploy deployment on {server}...[/blue]")
    try:
        resp = requests.post(
            f"{server}/api/deploy",
            json=payload,
            headers=headers,
            timeout=30,
        )
        resp.raise_for_status()
        console.print(f"[bold green]✓ Dokploy deployment triggered.[/bold green]")
        console.print(f"  Response: {resp.json()}")
    except requests.HTTPError as exc:
        console.print(f"[red]Dokploy API error: {exc}\n{exc.response.text}[/red]")
        sys.exit(1)
    except requests.ConnectionError:
        console.print(f"[red]Could not connect to Dokploy server at {server}[/red]")
        sys.exit(1)
