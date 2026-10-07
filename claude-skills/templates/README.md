<a href="../../README.md"><img src="../../assets/logo-bsg-holding.png" alt="Beyond Scale Group" height="40"></a>

**[Beyond Scale Group](../../README.md)** · [BSG Stack](../../README.md) · [Claude Skills](../README.md)

---

# `templates/` — agent intent-file starters

Blank starter documents you copy into a target repo to steer a BSG agent.
Each template is **read by one agent** — fill in the sections that apply,
leave the rest blank, and the agent picks up the signals on its next tick.

Copy a template into the repo root (or `.bsg/`) and edit it:

```bash
cp claude-skills/templates/ROADMAP.md ROADMAP.md
```

## The templates

| Template | Read by | Purpose |
|---|---|---|
| `ROADMAP.md` | `@po-manager` | Vision, active milestone, priorities — steers plan adherence & triage. |
| `ARCHITECTURE.md` | `@tech-lead` | Architecture intent, constraints, and decisions to record as ADRs. |
| `QUALITY.md` | `@qa` | Coverage targets, critical paths, regression-risk priorities. |
| `SECURITY.md` | `@security` | Security policy (GitHub convention): supported versions, reporting. |
| `SEO.md` | `@seo` | Target keywords, priority pages, structured-data intent. |
| `MARKETING.md` | `@marketing` | Positioning, audience, content-calendar seed. |
| `BRAND.md` | `@storytelling` | Voice, tone, key messages — the narrative bible seed. |
| `COMMS.md` | `@pr-comms` | Announcement channels, newsworthiness thresholds, press-kit intent. |

These are **intent files**: optional context an agent reads to adjust its
defaults. They're distinct from the agents' own dated reports, which land
under `.bsg/reports/`. See [`../../CLAUDE.md`](../../CLAUDE.md) for the `.bsg/`
directory convention and [`../agents/README.md`](../agents/README.md) for the
agent catalog.

---

<sub>Source of truth — edit here and PR back. See [`../INSTALL.md`](../INSTALL.md).</sub>
