# Active Context

## Current Session Focus
- Initialized `CLAUDE.md` (comprehensive operational guide)
- `CLAUDE.md` was subsequently replaced by a hook/linter redirect pointing to `AGENTS.md`
- `AGENTS.md` now contains the full operational guide content
- Initializing `.memory-bank/` for the first time (no prior Memory Bank existed)

## Current State of Key Files
| File | State |
|---|---|
| `AGENTS.md` | Full operational guide — commands, style, architecture, constraints |
| `CLAUDE.md` | Redirect stub pointing to `AGENTS.md` |
| `.memory-bank/` | Being initialized now (this session) |
| `pwd.yml` | Demo file — current pinned version: ERPNext v16.22.0 |

## Open Questions / Planned Work
- **Nomad HCL:** Project purpose includes HashiCorp Nomad HCL deployment, but no `.nomad` files exist yet
- **Dokploy:** Mentioned in project goals but no configuration present
- **AGENTS.md vs CLAUDE.md:** The linter hook rewrites `CLAUDE.md` to a redirect — always update `AGENTS.md` as the canonical guide, not `CLAUDE.md`

## Last Significant Actions
1. Comprehensive `CLAUDE.md` written based on full codebase exploration
2. Linter hook replaced `CLAUDE.md` content with a redirect to `AGENTS.md`
3. Memory Bank initialized (this session, 2026-06-10)

## Next Recommended Actions
- Run `/workflow:understand` to deepen context for any new feature work
- When adding Nomad or Dokploy configs, update `AGENTS.md` with relevant commands
- Run `pre-commit install` before making any commits
