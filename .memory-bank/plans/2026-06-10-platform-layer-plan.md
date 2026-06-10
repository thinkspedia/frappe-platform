# Plan: Unified Frappe Platform Layer (Option A)
Date: 2026-06-10

## Selected Option
Option A — Platform Layer (`platform/` subdirectory)

## Rationale
- Zero upstream conflict; frappe_builder root files untouched
- Clean extraction boundary if platform/ becomes its own repo
- org-bench CLI abstracts path complexity for developers
- Lowest risk: purely additive

## Deliverables

### File Structure
```
platform/
├── Dockerfile                    # 4 stages: base, development, prod-build, production
├── apps.json                     # org app registry (private repos)
├── .env.example                  # all vars with comments
├── docker-compose.dev.yml        # full local stack + bootstrap service
├── scripts/
│   ├── bootstrap.sh              # idempotent first-run: new-site + install-app loop
│   └── configure-site.sh        # write site_config.json host_name from .env
├── nomad/
│   └── frappe.nomad.hcl          # prestart migration + web/worker/scheduler groups
├── dokploy/
│   └── dokploy.yml               # Dokploy compose manifest
└── cli/
    ├── pyproject.toml
    └── org_bench/
        ├── __init__.py
        ├── dev.py                # setup, start, new-app
        ├── build.py              # build --tag
        └── deploy.py             # deploy --env --tag
```

## Key Technical Decisions
- Private repo auth: Docker BuildKit `--secret` (never baked into layers)
- Nomad migration: `lifecycle { hook = "prestart" }` batch task before web group
- Nomad zero-downtime: `update { max_parallel = 1, canary = 1 }`
- .env as source of truth: consumed by docker-compose.dev.yml AND nomad (env { file })
- Dokploy: Dokploy-compatible docker-compose with service labels
- org-bench CLI: Python Click, installable via `pip install -e platform/cli`

## Verification Steps
1. `org-bench dev setup` → .env created, images pulled
2. `org-bench dev start` → stack up, bootstrap creates site on first run
3. `org-bench build --tag v1.0.0` → production image built and tagged
4. `org-bench deploy --env staging --tag v1.0.0` → Nomad job dispatched, health checked
