# Press Release Drafting

How `draft.sh` generates a press-release stub.

## Structure

```markdown
---
release: v2.4.0
publishedAt: 2026-04-18
status: draft
confidential: true
---

# Press Release — v2.4.0 Webhook Reliability

## Headline
_(One line. What changed that the world cares about.)_

## Lead paragraph
[Company] today announced version 2.4.0, introducing automatic
webhook retry with exponential backoff. _(Continue with one more
sentence of context.)_

## Supporting paragraph
_(Expand on user value. Keep it concrete — what can the user now do
that they couldn't before?)_

## Quote
> _(Founder / product lead quote. The agent will not write this.
> A human supplies it.)_

## Boilerplate
_(Pulled verbatim from `comms/press-kit/boilerplate.md` if present.
Otherwise a placeholder pointing to the missing file.)_

## Contact
_(Pulled from `comms/press-kit/contact.md` if present.)_

---

*Auto-drafted by @pr-comms on 2026-04-20 from release v2.4.0 notes.
Human review required before external distribution. CONFIDENTIAL —
do not publish without approval.*
```

## Inputs

- **Release metadata** — tag, name, body, publishedAt.
- **Press-kit boilerplate** — if `comms/press-kit/boilerplate.md`
  exists, the script inlines its content.
- **Narrative bible tone target** — if `brand/NARRATIVE.md` is
  available, the tone-target line is included in the draft so the
  writer matches the brand voice.
- **Repository visibility** — private repos get a CONFIDENTIAL
  header.

## How to run

```bash
# Plan only
bash scripts/draft.sh

# Write stubs
bash scripts/draft.sh --write
```

## Output schema

```json
{
  "plan": [
    { "release": "v2.4.0", "title": "Webhook Reliability",
      "path": "comms/press-releases/2026-04-18-v2.4.0-webhook-reliability.md" }
  ],
  "generated": [],
  "confidential": true
}
```

## Hard rules

1. **Don't fill placeholder quotes or customer stories.** Those are
   the whole point of human authorship.
2. **Don't publish.** The draft lands on disk as a working file.
3. **Don't overwrite** an existing draft. `draft.sh` is idempotent
   — if the file already exists, it's left alone.
4. **Respect `--write` opt-in.** Plan mode is the default.

## What NOT to do

- **Don't draft security-advisory responses.** The events reporter
  flags them; human communications team handles the messaging.
- **Don't adjust the boilerplate.** If the boilerplate is stale, the
  press-kit reporter surfaces it — updating the boilerplate is a
  separate, explicit ask.
- **Don't guess at company facts** (ARR, employee count, customer
  count). These come from the press kit or they stay as placeholders.
