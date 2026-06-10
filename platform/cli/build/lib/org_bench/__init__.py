"""
org-bench — Unified Frappe platform CLI.

Install:  pip install -e platform/cli
Usage:    org-bench --help
"""

import click
from org_bench.dev import dev
from org_bench.build import build
from org_bench.deploy import deploy


@click.group()
@click.version_option("0.1.0", prog_name="org-bench")
def cli() -> None:
    """Frappe Platform CLI — manage dev, build, and deploy workflows."""


cli.add_command(dev)
cli.add_command(build)
cli.add_command(deploy)
