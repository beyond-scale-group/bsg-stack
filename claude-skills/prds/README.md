<a href="../../README.md"><img src="../../assets/logo-bsg-holding.png" alt="Beyond Scale Group" height="40"></a>

**[Beyond Scale Group](../../README.md)** · [BSG Stack](../../README.md) · [Claude Skills](../README.md)

---

# `prds/` — product requirement documents

The specs the BSG agents and skills were built from. Each PRD captures the
goal, scope, and acceptance criteria for one agent or skill — read them to
understand **why** a piece works the way it does, before changing it.

These are historical/reference design docs. The live behavior contract is in
each agent's own frontmatter + [`../../CLAUDE.md`](../../CLAUDE.md); a PRD and
the shipped agent can drift, so treat the agent file as source of truth for
behavior and the PRD as background.

## The specs

| PRD | Subject |
|---|---|
| `001-security.md` | Security agent |
| `002-qa.md` | QA agent |
| `003-tech-lead.md` | Tech-lead agent |
| `004-seo.md` | SEO agent |
| `005-marketing.md` | Marketing agent |
| `006-storytelling.md` | Storytelling agent |
| `007-pr-comms.md` | PR / comms agent |
| `008-md-to-office.md` | `md-to-office` skill |

Naming: `NNN-<slug>.md`, zero-padded sequential. Add the next number when you
spec a new agent or skill.

---

<sub>See [`../agents/README.md`](../agents/README.md) for the shipped agents and
[`../INSTALL.md`](../INSTALL.md) for the install catalog.</sub>
