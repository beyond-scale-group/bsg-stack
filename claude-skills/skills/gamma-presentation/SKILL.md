---
name: gamma-presentation
description: >
  Generate professional presentations and documents from markdown files
  using the Gamma API. Reads YAML frontmatter for format, text mode,
  slide count, language, and folder targeting. Writes the generated URL
  back into the source file. Use when the user asks to "create a
  presentation", "generate slides", "gamma presentation", "convert
  markdown to slides", "gamma from prompt", or when a source file has
  `gamma:` in YAML frontmatter.
version: 0.1.0
output: chat
auto-implements: []
never-auto-implements: []
model: haiku
---

# Gamma Presentation Skill

Generate presentations and A4 documents from structured markdown via
the [Gamma public API](https://gamma.app). The skill reads content and
configuration from a `.md` file with YAML frontmatter, calls the API,
and writes the generated URL back into the source file.

## Hard rules

1. **Scripts do the work.** This SKILL.md narrates; `scripts/gamma-api.js`
   contains the actual logic. Do not re-implement API calls in-chat.
2. **Frontmatter is the config surface.** All generation parameters come
   from the source file's YAML frontmatter — never prompt the user for
   values that belong in frontmatter.
3. **Write back to the source.** After a successful generation, update the
   source file's frontmatter with `generatedUrl` and `generatedAt`.
4. **Language quality matters.** When `language: fr`, enforce proper French
   accents and grammar in the content before sending. Use numeric
   `MM/YYYY` date format in tables for better Gamma rendering.
5. **Never hardcode API keys.** The `GAMMA_API_KEY` environment variable
   is the only auth path.

## Source file format

Users write `.md` files with YAML frontmatter:

```yaml
---
gamma:
  format: presentation        # presentation | document
  textMode: generate          # generate | condense | preserve
  numCards: 10                # 1-60 (default: 10)
  folderId: optional-id       # Gamma folder ID
  textAmount: medium          # brief | medium | detailed | extensive
  language: en                # ISO language code
  dimensions: 16x9            # 16x9 | 4x3 | a4 | letter
  themeId: optional-theme-id  # Gamma theme ID
---

# Content starts here...
```

## Available scripts

All scripts live in `scripts/`. `gamma-api.js` is the single entry point.

| Script | Purpose |
|---|---|
| `gamma-api.js` | Orchestrator. `node gamma-api.js generate <file.md>` parses frontmatter, calls the API, writes back the URL. `node gamma-api.js folders` lists workspace folders. |

### Commands

```bash
# Generate a presentation or document from a markdown file:
node scripts/gamma-api.js generate <file.md>

# List available Gamma workspace folders:
node scripts/gamma-api.js folders
```

## API parameters

| Parameter | Frontmatter key | Type | Default | Description |
|---|---|---|---|---|
| `inputText` | (file body) | string | — | Markdown content (max 100,000 tokens) |
| `textMode` | `gamma.textMode` | string | `generate` | `generate` / `condense` / `preserve` |
| `format` | `gamma.format` | string | `presentation` | `presentation` / `document` |
| `numCards` | `gamma.numCards` | integer | `10` | Number of slides (1-60) |
| `textOptions.amount` | `gamma.textAmount` | string | `medium` | `brief` / `medium` / `detailed` / `extensive` |
| `textOptions.language` | `gamma.language` | string | `en` | Output language (ISO code) |
| `cardOptions.dimensions` | `gamma.dimensions` | string | `16x9` | `16x9` / `4x3` / `a4` / `letter` |
| `folderIds` | `gamma.folderId` | string | — | Gamma folder ID (auto-detected from repo name if omitted) |
| `themeId` | `gamma.themeId` | string | — | Gamma theme ID |

## Auto-folder detection

When `folderId` is omitted, the script reads the current Git repo name
and matches it against Gamma workspace folders. If a folder with the
same name exists, it is used automatically. This lets teams organize
generated content by project without manual folder management.

## Intent routing

| User says… | Do… |
|---|---|
| "Create a presentation from X.md", "generate slides" | `node scripts/gamma-api.js generate X.md` |
| "Convert this to a document", "gamma document" | Ensure frontmatter has `format: document`, then `node scripts/gamma-api.js generate X.md` |
| "List my Gamma folders" | `node scripts/gamma-api.js folders` |
| "Set up Gamma", "gamma API key" | Tell user to set `GAMMA_API_KEY` in their shell profile |
| "Create a new presentation about X" | Create a `.md` file from `templates/example.md`, fill content, run generate |

## Error handling

| Condition | Behavior |
|---|---|
| Missing `GAMMA_API_KEY` | Exit with message: "Set GAMMA_API_KEY in your environment" |
| API returns error | Print the error message and status code |
| File not found | Print "File not found" and exit |
| No `gamma:` frontmatter | Use defaults (presentation, generate, 10 cards, en, 16x9) |
| Content exceeds 100k tokens | Warn and truncate |

## Dependencies

- Node.js 18+
- `GAMMA_API_KEY` environment variable

No npm packages required — uses Node.js built-in `fetch`.

---

## How to improve this skill

This file is a cached copy of `claude-skills/skills/gamma-presentation/SKILL.md` in
[beyond-scale-group/bsg-stack](https://github.com/beyond-scale-group/bsg-stack).
That repo is the single source of truth — `~/.claude/skills/gamma-presentation/SKILL.md`
is overwritten every time the BSG install flow runs.

If the user asks you to improve, fix, or extend this skill, do **not** edit
the local file. Instead:

1. `gh repo clone beyond-scale-group/bsg-stack` (or work in an existing clone)
2. Edit `claude-skills/skills/gamma-presentation/SKILL.md` on a feature branch
3. Open a pull request against `main`

Bug reports and ideas without a fix → open an issue on the same repo.
