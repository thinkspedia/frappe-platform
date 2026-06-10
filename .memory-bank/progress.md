# Progress

## What Is Working (Confirmed in This Session)
- [x] Full repository structure explored and documented
- [x] `AGENTS.md` — comprehensive operational guide written and confirmed as canonical
- [x] `CLAUDE.md` — redirect stub in place pointing to `AGENTS.md`
- [x] `.memory-bank/` — initialized (this session, 2026-06-10)
- [x] All 18 override files present and documented
- [x] CI/CD workflows (12 total) present and categorised
- [x] Test suite (`tests/`) present with conftest, fixtures, and integration tests
- [x] Pre-commit hooks configured

## What Is Planned But Not Yet Implemented
- [ ] HashiCorp Nomad HCL job files (`.nomad` / `.hcl` deployment jobs)
- [ ] Dokploy deployment configuration
- [ ] Production deployment to local environment (end-to-end test)

## Known Constraints and Gotchas
1. **`pwd.yml` is auto-generated** — never edit manually; use `.github/scripts/update_pwd.py`
2. **`CLAUDE.md` gets rewritten by a hook** — always maintain `AGENTS.md` as the source of truth
3. **No git commits in this working copy** — all files are currently untracked
4. **No Frappe app code here** — this is infrastructure only; Frappe apps live in separate repos
5. **Tests require a live Docker stack** — `pytest tests/` will fail without services running

## Session History
| Date | Action |
|---|---|
| 2026-06-10 | Initial `CLAUDE.md` generated (operational guide) |
| 2026-06-10 | Hook rewrote `CLAUDE.md` to redirect; content lives in `AGENTS.md` |
| 2026-06-10 | `.memory-bank/` initialized (first time) |
