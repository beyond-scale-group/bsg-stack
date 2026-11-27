---
name: candidature-concours
description: >-
  Prepare and fill an online application form (startup competition, accelerator or
  incubator programme, open call, call for projects) without surprises: blank survey of
  the form first (real field types, conditional questions, hidden character limits
  measured before any answer is written), answers fitted to the limits, dry-run fill
  checked field by field, then one single submission on an explicit human yes, with
  screenshots before and after. Use when the user says "dépose la candidature", "remplis
  le formulaire de candidature", "postuler à ce programme", "concours", "appel à
  candidatures", "accélérateur", "apply to this programme", "fill this application form",
  or shares an Airtable / Typeform / Google Forms application link.
version: 0.1.0
model: sonnet
---

# Application form filler (candidature-concours)

Prepare and fill an online application for the group: competitions, accelerator
programmes, open calls. Built from the first real filing done this way:
**TotalEnergies On, Batch #8 (2026-11-27)**, a public Airtable form of 38 questions,
filed in one single submission by Donna. It is the running example below; the skill
works for any form.

**You prepare and you fill. You never submit, send the cover email, or merge a PR
without an explicit yes from the user for THAT action** (see "The three yeses").

## Setup

Two Node scripts drive a headless browser with Playwright:

```bash
npm install -g playwright-core          # once; never `npx playwright install`
export NODE_PATH="$(npm root -g)"       # so the scripts find playwright-core
S=~/.claude/skills/candidature-concours/scripts
D="./candidature-$(date +%Y%m%d-%H%M)"; mkdir -p "$D"
```

The scripts use the installed Google Chrome (`channel: "chrome"`). On a machine without
it (a Linux server), set `CHROMIUM_PATH=/usr/bin/chromium`.

## Step 1 — blank survey of the form

Do it **at the very start, before writing a single answer**.

```bash
PROBE=1 node "$S/inspect-form.js" "<form url>" "$D"
jq -c '.questions[] | {n, question: .question[0:70], type, required, options, measured_limit, announced_limit, attachment}' "$D/survey.json"
```

For every question: exact label, real type (short text, long text, rich text, single
choice, checkboxes, dropdown, attachment), required flag, exact options, and the
**measured** character limit. `PROBE=1` pastes a 5,040-character text into each text
field, reads what the field keeps and any new error line on the page, then clears the
field. The submit button is never touched. Outputs: `survey.json`, `blank-form.png`.

**Then map the branches.** A question can appear or disappear depending on an answer
("Other", "Europe", "Yes", "None"…). The dry-run fill (step 3) lists every question that
appeared outside the plan; iterate until the map is complete.

If `alerts` mentions a captcha or a sign-in: stop and hand back to the user.

## Step 2 — answers, within the constraints

- **One source of truth**: a file of answers validated by the user, one per question,
  keyed by the exact label from the survey. A choice is copied **exactly** as the option
  ("€0-200K Annual Recurring Revenues", not "0-200k").
- **Measure every answer** against its limit, in characters AND words
  (`printf %s "$TEXT" | wc -m`, `wc -w`). Over the limit: never cut silently. Propose a
  short version with its count ("273 of 300 characters") and wait for the yes.
- **What does not fit** (product detail, demo links, contacts) goes into the cover email
  or the deck — say where.
- **Never decide for the user** on a choice that commits them (figures, cap table, team
  size, checkboxes the answer file does not cover, a free-text answer that turns out to be
  a checkbox list). Ask, with the exact options and your recommendation. Only exception:
  an explicit "do your best" — then choose, and say precisely what you chose.
- **Every site and page cited in the answers must be live before filing**, checked in a
  browser (screenshot, expected content present — not just HTTP 200).

## Step 3 — dry-run fill

Turn the answers into a plan:
`[{"q": "start of the label", "type": "text|choice|checkboxes|multi-select|file", "value": "..." or ["..."]}]`
(absolute paths for files).

```bash
OUT="$D" node "$S/fill-form.js" "<form url>" "$D/plan.json"
jq '{ok, issues, questions_outside_plan, limit_messages}' "$D/check.json"
```

The script fills, reads every field back (text read = text planned, choices found,
attachments present), collects fields rejected by the form, limit messages, questions
that appeared outside the plan, and takes a full-page `filled-form.png`. **Without the
three submit conditions it stops there** (`STOP without submitting`).

Any anomaly stops everything: unknown question, limit exceeded, invalid field, missing
attachment. Describe it with the screenshot, propose a fix, wait.

## Step 4 — the submission, exactly once

Only after the user said yes to THIS submission with THIS content, and the dry run
passed with no issue.

```bash
date -u +%FT%TZ > "$D/GO"     # trace of the yes
OUT="$D" SUBMIT=1 GO="$D/GO" BUTTON="<exact submit button text>" node "$S/fill-form.js" "<form url>" "$D/plan.json"
head -20 "$D/after-submit.txt"
```

- The `SUBMITTED` marker is written **before** the click: the script refuses any second
  run. If no confirmation shows up, screenshot and stop. **Never retry** — report what
  the screen shows.
- Two screenshots, always: `filled-form.png` (before) and `confirmation.png` (after).
- File with the account the user asked for (TotalEnergies On: Donna's address, with the
  founder as the named person).

## After the submission

Only once the confirmation is on screen, each on its own yes:

- **Cover email** (programme contact, team in copy): prepare a draft, check it says the
  same thing as what was filed, send that draft on the yes.
- **Site or case-study update** ("application filed on …"): a PR, never merged by you.
- **A lessons-learned note**: what worked, the traps — new ones go into this skill.

## The three yeses

Three actions, three separate yeses from the user: submitting the form, sending the
email, the PR or its merge. A yes for one never covers the next. An unrelated message
in between is not a yes.

## What you never work around

- **Captcha, two-factor, sign-in**: stop, hand back with the screenshot. No captcha
  solving service, never a password in the chat.
- **Programme rules** (who may file, whether AI-prepared files are accepted): check the
  rules page and flag any doubt before filing.

## Traps met (2026-11-27, TotalEnergies On)

- **Hidden limit**: the use-case question accepted 300 characters, with no mention before
  typing; the planned text was 4,442. The rejection only shows once the text is pasted,
  and the message sits **outside** the question block (hence the page-text diff in the
  probe). Re-surveyed the same day: the value-proposition question has the same
  300-character limit, and two questions announced as "100 words" actually stop at 1,000
  characters; "200 words maximum" is announced but not enforced.
- **Conditional questions**: ticking "Europe" adds a required question (countries of
  activity) invisible on the blank form; "Did not raise money" and "None" hide the
  last-round date and the business contact. "38 questions" was wrong both ways.
- **Free text that is a checkbox list**: "What do you need in order to generate results
  within 6 months?" was a checkbox list ("Other" opens "If other, please specify"), not a
  paragraph. HQ country is a dropdown: "France", not "France (Lyon)". An "Other" option
  may open no detail field at all: the planned text then has nowhere to go.
- **Airtable attachments**: multi-step upload dialog; wait for it to close, then check the
  file shows in the field.
- **Cookie banner** to close first (Airtable: inside a shadow root; the "Reject All"
  button is still found by its role).
- **URL fields**: a click can time out; a direct `fill` works. Non-URL text is rejected
  ("Please enter a valid URL.").
- **No draft, no edit after submission** on this kind of form: hence the full dry run, the
  check, and the marker before the click.

## Your answer

Short, result first, readable by a non-developer:

- survey: number of questions, their types in one line, the limits that matter, the
  conditional questions found, any blocker (captcha, sign-in);
- dry run: ready or not; if not, each issue in one line and the question to decide, with
  the exact options;
- submission: filed or not, the confirmation sentence read on screen, the screenshots,
  what is waiting for a yes next.

## What you never do

- Submit, send an email, or merge a PR without the user's yes for that action.
- Cut an answer silently, or pick an option that commits the user without their consent.
- Create an account on a site unless asked.
- Put a figure in an answer that does not come from a source (accounts, repos, the user):
  a gap is flagged, never filled in.

---

## How to improve this skill

This file is a cached copy of `claude-skills/skills/candidature-concours/SKILL.md` in
[beyond-scale-group/bsg-stack](https://github.com/beyond-scale-group/bsg-stack).
That repo is the single source of truth -- `~/.claude/skills/candidature-concours/SKILL.md` is
overwritten every time the BSG install flow runs.

If the user asks you to improve, fix, or extend this skill, do **not** edit
the local file. Instead:

1. `gh repo clone beyond-scale-group/bsg-stack` (or work in an existing clone)
2. Edit `claude-skills/skills/candidature-concours/SKILL.md` on a feature branch
3. Open a pull request against `main`

Bug reports and ideas without a fix -> open an issue on the same repo.
