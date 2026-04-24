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

## PPTX (PR #3, not yet implemented)

When the pptx renderer lands, the convention will be:

- `# Title` → title slide (layout: `title`)
- `## Section` → section-header slide (layout: `section`)
- `### Content` or plain H2 with bullets → content slide (layout: `content`)
- `---` (horizontal rule) → explicit slide break
- Tables and images inside a section go on the same content slide

## XLSX (PR #4, not yet implemented)

Each top-level markdown table becomes one worksheet. Sheet names come
from the preceding H2 (if any) or fall back to `Sheet1`, `Sheet2`, …

## Frontmatter hint

The auto-target detector (post v0.1) will look at optional YAML
frontmatter:

```markdown
---
target: pptx
---

# Slide 1
...
```

This pins the target without needing a CLI flag.
