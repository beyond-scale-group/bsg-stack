# Messaging Audit

How to do a lightweight narrative check of landing-page copy in the
repo.

## Scope

Messaging audit is **LLM-driven**, not script-driven. The skill
provides the raw signals (what marketing files exist, what they
claim, what features shipped); the agent composes a narrative
verdict — is the messaging current, accurate, and consistent with
the product?

Out of scope:

- **Copy grading** (tone, voice, effectiveness).
- **A/B-test recommendations.**
- **External landing pages.** CMS-hosted copy is invisible to this
  skill.

## When to use

| Trigger                                                | Response                                                                     |
| ------------------------------------------------------ | ---------------------------------------------------------------------------- |
| "audit landing page messaging"                         | Read all files under `marketing/` and top-level README; compare to releases  |
| "is the landing page up to date"                       | Same, focused on the most recent N releases                                  |
| "does the README still match what we ship"            | Compare README feature list to release / milestone titles                    |

## Inputs

All of these come from `collect.sh` output:

- `marketed` — array of `{ file, claims[] }` from every file under
  `marketing/` and the top-level README.
- `shipped` — array of `{ version, title, releasedAt }` from `gh
  release list`.
- `alignment` — the `alignment.sh` output if you want the quick
  summary instead.

## Output format (narrative)

```markdown
## Messaging verdict

The landing copy in `marketing/landing-auth.md` still references
"OAuth1 support" as a key feature, but the current release line
(v2.3+) only ships OAuth2. Suggest updating the Authentication
section.

The homepage README accurately reflects the feature matrix as of
v2.4.0. No action needed.
```

## Hard rules

1. **Don't invent claims.** Only cite text that the script actually
   extracted.
2. **Cite file paths.** Every finding gets a file reference so the
   marketing lead knows where to edit.
3. **Don't draft replacement copy.** Recommend an update; leave
   the actual wording to the marketing team.
4. **Respect `.marketingignore`.** Some files (customer-specific
   landing pages, archival content) are intentionally out of date;
   the ignore file lists them.

## Pitfalls

- **Past-tense vs present-tense.** A blog post from 2024
  correctly uses past-tense product descriptions. Don't flag
  historical content as "out of date" — only flag content whose
  path looks present-tense (landing pages, product pages, homepage).
- **Marketing copy without a date.** If you can't tell when the
  copy was written, treat claims as current and check them against
  the present-tense feature set.
