# Test Plan Generation

How to draft a targeted test plan for a feature, PR, or refactor.

## Scope

Test-plan generation is **LLM-driven**, not script-driven. The skill
provides the raw signals (risk scores, coverage gaps, CI history); the
agent composes a checklist tailored to the change at hand.

Out of scope for this reference:
- Generating actual test code. The agent describes what to test, not
  how to test it.
- Full test strategy documents. The output is a focused checklist for
  one change, not a multi-page plan.

## When to use

| Trigger                                                     | Response                                                       |
| ----------------------------------------------------------- | -------------------------------------------------------------- |
| "test plan for PR #123"                                     | Fetch the PR diff, run `risk.sh` on changed files, draft plan |
| "what should I test before merging feature X"               | Same, with feature branch diff                                 |
| "plan tests for the new payment flow"                       | Broad ask — clarify which files/modules are in scope first     |

## Inputs the agent needs

1. **What changed** — a list of files, ideally from a PR diff or
   `git diff <base>...HEAD`.
2. **Current coverage for those files** — from `coverage.sh`.
3. **Churn on those files** — from `risk.sh`.
4. **Existing tests in the adjacent directories** — via `Glob` on
   `tests/**/*<file>*`, `**/*<file>*.spec.ts`, etc.

## Output format

```markdown
# Test Plan — PR #123: Add webhook retry logic

## Changed files (4)
- `src/webhook/retry.ts` (new, 142 LOC)
- `src/webhook/index.ts` (+23 / -8)
- `tests/webhook/retry.spec.ts` (new, 67 LOC)
- `docs/webhooks.md` (+11)

## Coverage of changed non-test files
| File                      | Current | Target |
|---------------------------|---------|--------|
| src/webhook/retry.ts       | 0%      | 80%+   |
| src/webhook/index.ts       | 72%     | 72%+   |

## Happy path
- [ ] Retry succeeds on transient 5xx
- [ ] Retry surfaces after max attempts
- [ ] Exponential backoff delays honored

## Edge cases
- [ ] Simultaneous requests to same endpoint don't double-retry
- [ ] Retry loop cancelled on deploy (SIGTERM)
- [ ] Non-retryable errors (400) surface immediately

## Regression surface
- `retry.ts` is new — no regression surface yet.
- `index.ts` changes affect the public `send()` API — retest every
  existing webhook test.

## Open questions
- Should retry state persist across process restarts?
- What's the observability budget for retry metrics?
```

## Hard rules

1. **Don't invent file-level facts.** Coverage numbers and churn must
   come from `coverage.sh` / `risk.sh`, not reasoning.
2. **Don't promise a specific target coverage %** without checking the
   project convention first (may be in `README.md`, `CONTRIBUTING.md`,
   or a CI config).
3. **Don't write the tests.** This is out of scope. The agent plans;
   the developer implements.
4. **Be specific about edge cases.** "Edge cases" alone is not a
   checklist item — name them.
