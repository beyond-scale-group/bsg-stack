# Markdown conventions for `md-to-office`

Short guide for authoring markdown that renders well through this skill.

## DOCX (v0.1)

Pandoc handles the common markdown subset cleanly. Stick to:

- **Headings**: `#` / `##` / `###` map to Word `Heading 1..3`. Don't go deeper than H4.
- **Lists**: dash bullets (`-`) and numbered (`1.`). Nested lists are supported two levels deep in most reference templates.
- **Tables**: GitHub-flavored pipe tables. Column widths are auto. For precise widths, hand-edit the output DOCX.
- **Code**: fenced blocks with a language tag. The reference template's `Source Code` style is applied.
- **Emphasis**: `**bold**`, `*italic*`. Avoid underscores for emphasis — some reference-docs miss them.
- **Links**: `[text](url)`. Pandoc renders them as Word hyperlinks.
- **Images**: `![alt](path/to/img.png)`. Use relative paths so pandoc can resolve them at render time.

## PPTX

- `# Title` → title slide (layout 0: Title Slide). Body text becomes subtitle.
- `## Section` → content slide (layout 1: Title and Content)
- `### Sub` → bold subheading within current slide
- `---` (horizontal rule) → explicit slide break
- Bullet lists (dash, asterisk, numbered) → bulleted text frame with nesting (up to 2 levels)
- GFM pipe tables → PPTX table shape positioned below content
- `![alt](path)` → embedded picture (relative paths resolved from source dir)
- `**bold**` / `*italic*` → inline formatting in runs
- Fenced code blocks → monospace (Courier New) text

## XLSX (PR #4, not yet implemented)

Each top-level markdown table becomes one worksheet. Sheet names come
from the preceding H2 (if any) or fall back to `Sheet1`, `Sheet2`, …

## Frontmatter hint

The auto-target detector reads optional YAML frontmatter:

```markdown
---
gamma:
  format: presentation
---

# Slide 1
...
```

Supported fields (first match wins):
- `gamma.format: presentation` → PPTX
- `gamma.format: document` → DOCX
- `target: pptx` → PPTX
- `target: docx` → DOCX

This pins the target without needing a CLI flag. An explicit
`--target` override always wins over frontmatter.
