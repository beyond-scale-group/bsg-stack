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
  or shares an Airtable / Typeform / Google Forms application link, an Agorize challenge
  page, or needs the sponsor's partner programme enrolment or an archive of the answers sent.
version: 0.3.0
model: sonnet
---

# Application form filler (candidature-concours)

Prepare and fill an online application for the group: competitions, accelerator
programmes, open calls. Built from two real filings on 2026-11-27:
**TotalEnergies On, Batch #8**, a public Airtable form of 38 questions, filed in one
single submission by Donna; and **Microsoft GenAI Studio**, filed on the Agorize
platform behind an account, 100 % complete. They are the running examples below; the
skill works for any form (see "Known platforms").

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

## Known platforms

Identify the platform first: it decides what you can do yourself.

**Public one-page form (Airtable, Typeform, Google Forms)** — TotalEnergies On case.
No account: every question is visible on the blank form, except conditional ones. No
draft, no edit after submission. Survey, fill and submission go through the scripts of
steps 1, 3 and 4; traps under "Traps met".

**Agorize (challenge platform)** — Microsoft GenAI Studio case (2027 cohort, filed on
2026-11-27 at 10:34, 100 % complete).

- **Public pages first**: presentation, phase calendar (`.../pages/challenge-phases`),
  FAQ (`.../pages/faq`), rules (`.../agreements`). Extract the required documents, the
  conditions, the closing date AND time (e.g. "1 December, 23:55"), the shortlist and
  jury dates. Only the main document is announced there (a pitch deck).
- **The form is only visible once signed in.** Before it: account creation, email
  address confirmation, terms of use to accept, a "start-up" profile (required fields,
  e.g. development stage), the "Participer" button, the rules checkbox. **The person
  signs in themselves** (password, codes). Terms and rules: read and summarise them
  before they are ticked, and only with the person's consent. The blank survey only
  happens afterwards, once signed in; the scripts of steps 1, 3 and 4, which open a
  browser without a session, stop at the sign-in.
- **Multi-page form**: first an "application" card (project name, short description,
  image — the deck cover at 1024 × 576 px), then sections (general information,
  business model, tech roadmap, a sponsor-specific section). Fields seen: attachments
  (PDF deck, video), fixed lists (headcount range, sector with "Other", deployment
  mode, B2B/B2C), multiple checkboxes with "Other" to specify (cloud providers), yes/no,
  legal identifier (SIRET), links, free texts, a final "other information or links"
  field.
- **Displayed limits**: 30 characters for the application name, 255 for the
  description. Other limits are still to be measured: add them here.
- **Injected values rejected**: Agorize did not keep values filled directly by script.
  Type every answer on the keyboard, field by field (in Playwright: `pressSequentially`,
  not `fill`), then read it back.
- **Completion**: the application shows a percentage; file at 100 %. After filing: an
  application ID and the submission time, to record (archive, below).
- **Outage mid-fill**: HTTP 500 errors on every page. Stop, do not insist; resumed the
  next day from the answers file, the single source of truth.

**Microsoft AI Cloud Partner Program (Partner Center)** — an example of a sponsor's
partner programme: the GenAI Studio rules cited a listing on the Microsoft Marketplace,
hence enrolment on the filing day. It is separate from the application form.

- Start it early: verification takes 3 to 5 business days, sometimes more. Started
  before the jury, it lets you say "enrolled, verification in progress"; the
  application document says so too.
- To gather: a company work account, an administrator entitled to commit the company,
  the company name and address **exactly as on the Kbis** (compared with official
  documents; the country cannot be changed later), a Kbis extract, an ID document,
  proof of the domain name, a work email on the domain, the publisher name shown to
  customers (distinct from the company name).
- **The person does it themselves**: password, verification codes, bank card, two-factor
  authentication, accepting the agreements, final submission and supporting documents
  (Kbis, domain proof).
- After verification: tax and payout profiles (tax form to confirm with the
  accountant).
- Traps (2026-11-27):
  - personal Microsoft account refused: a work tenant was created (bank card requested,
    nothing charged, two-factor authentication);
  - the `.onmicrosoft.com` domain can never be changed: pick a short one;
  - company name prefilled with the brand: corrected twice to match the Kbis;
  - registration number (SIRET) field locked: record it in the application document;
  - the layout shifted when a field was added and an entry went into the wrong field:
    read every field back right after typing it.

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

- **The applying entity first**, before filling anything: legal name, SIREN/SIRET and
  address matching the Kbis, even if the brand differs. The brand goes in the project
  name; a new company name is written "future <name>" next to the registered name.
- **One source of truth**: a file of answers validated by the user, one per question,
  keyed by the exact label from the survey. After filing it is updated with the answers
  as sent; after an outage, you resume from it. A choice is copied **exactly** as the option
  ("€0-200K Annual Recurring Revenues", not "0-200k").
- **Measure every answer** against its limit, in characters AND words
  (`printf %s "$TEXT" | wc -m`, `wc -w`). Over the limit: never cut silently. Propose a
  short version with its count ("273 of 300 characters") and wait for the yes.
- **What does not fit** (product detail, demo links, contacts) goes into the cover email
  or the deck — say where.
- **Never decide for the user** on a choice that commits them (figures, cap table, team
  size, checkboxes the answer file does not cover, a free-text answer that turns out to be
  a checkbox list). Required fields that commit the company — development stage, monthly
  cloud spend, funding, revenue — are always asked of the person, never estimated. Ask, with the exact options and your recommendation. Only exception:
  an explicit "do your best" — then choose, and say precisely what you chose.
- **Dated versions of one application document**: a draft ("26-11") that ends with its
  recommendation and the points to settle before filing, then "updated 27-11, filed".
  The title states the date and the status; the older version stays, to see what
  changed.
- **Rule conditions become actions**: cross every condition with the company's
  situation (requirement, situation, what is missing) and say what must be done. E.g.
  rules citing a listing on the sponsor's marketplace -> enrolment in its partner
  programme the same day ("Known platforms"). Also note the programme commitments
  (time, attendance, juries, deliverables).
- **The deck**: send the PDF, never the file with the speaker notes. Content that
  commits the company is validated by an executive, including the place of a
  technology that competes with the sponsor (a programme run by a vendor).
- **Everything announced** (features, timeline, customers) must be demonstrable in front
  of the jury: only write what will be by its date.
- **Heavy files**: a 29 MB video exceeded the tools' upload limit (10 MB); the person
  uploaded it themselves, with the link in the free "other information" field and a QR
  code in the deck as fallbacks. Before filing, check the link sharing: "Anyone with
  the link", not just the company domain.
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

**Archive the answers sent, right away**: a document "answers sent on <platform>
(<date>)" that reproduces the answers **as sent**, section by section, with the
application ID, submission date and time, completion, and every attachment (file name,
page count, video length). What was declared is re-read there before a jury, not in
the draft. Then update the application document (new dated version):

- the status: filed on …, at …, 100 % complete; the calendar that follows (shortlist,
  juries);
- a "what we declared" summary (company, team, model, funding, attachments);
- two lists, "Done" and "To do" (speakers' availability, any change to report to the
  organiser, such as a company name); this decision note holds the status of the
  application, with a copy in the Drive;
- jury dates: proposed for the calendar, created on the yes;
- the shortlist email must be watched, spam folder included: offer the person a mail
  watch, do not set it up unasked.

Then, only once the confirmation is on screen, each on its own yes:

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
- **A site outage** (HTTP 500 everywhere): stop, say so, and resume later from the
  answers file.

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
- Accept any agreement, terms of use or rules on the user's behalf: read and summarise
  them, the box is ticked with their consent.
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
