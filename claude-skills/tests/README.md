<a href="../../README.md"><img src="../../assets/logo-bsg-holding.png" alt="Beyond Scale Group" height="40"></a>

**[Beyond Scale Group](../../README.md)** · [BSG Stack](../../README.md) · [Claude Skills](../README.md)

---

# `tests/` — smoke & unit tests

Tests for the installer, the helper [`scripts/`](../scripts/), skill metadata,
and agent frontmatter. No test framework dependency — Python files are
plain-stdlib scripts you run directly, shell files are self-asserting.

Pattern: `test_<subject>.py` / `test_<subject>.sh`. Each exits non-zero on
failure and prints what broke.

## Run them

```bash
# One test
python3 claude-skills/tests/test_skills.py
bash    claude-skills/tests/test_pilot_candidates.sh

# All (from repo root)
for t in claude-skills/tests/test_*.py; do python3 "$t" || break; done
for t in claude-skills/tests/test_*.sh; do bash    "$t" || break; done
```

## What CI runs

The `ci-claude-skills-test` and `pipeline-regression` workflows gate every
PR on, among others:

| Test | Covers |
|---|---|
| `test_skills.py` | Every agent declares a valid `output` field + scope contract. |
| `test_agent_frontmatter.py` | Agent frontmatter shape (name, tools, lists). |
| `test_pilot_candidates.sh` | `list-pilot-candidates.sh` eligibility logic. |
| `test_bsg_paths.sh` | `.bsg/` vs legacy path resolution in `_bsg-paths.sh`. |
| `test_github_bus.sh` / `test_bus_handler.sh` | Coordination-bus primitives. |
| `test_circuit_breaker.sh` | Daily PR cap. |
| `test_assert_invariants.sh` | Pipeline regression invariants (baselines in `../../tests/pipeline-baselines/`). |
| `test_md_to_office*.py` | The `md-to-office` skill's render / scan / styling pipeline. |

Helpers `_skill_helpers.py` and `_md_to_office_helpers.py` are imported by the
test files, not run directly.

---

<sub>Add a test whenever you add a script or change a convention. See
[`../INSTALL.md`](../INSTALL.md).</sub>
