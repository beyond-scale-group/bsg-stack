# Marp markdown authoring reference

Quick reference for writing slide decks that convert well with
`md-to-slide.sh`. Full docs: https://marpit.marp.app/markdown

## Slide separation

Each `---` on its own line (with blank lines around it) starts a new slide:

```markdown
# Slide one

Content

---

# Slide two
```

## Front matter (global directives)

`md-to-slide.sh` injects `marp: true`, `paginate: true`, and a `footer:`
from the DESIGN.md company name automatically — anything you set yourself
wins. Useful extras:

```yaml
---
title: "Q3 Review"          # deck metadata (HTML <title>)
size: 16:9                  # or 4:3
paginate: true              # page number bottom-right
header: "Confidential"      # top of every slide
footer: "Acme Corp — 2026"  # bottom of every slide
---
```

## Per-slide (spot) directives

HTML comments starting with `_` apply to the current slide only:

```markdown
<!-- _class: lead -->       # title-slide styling (branded gradient, centered)
<!-- _class: divider -->    # section-divider styling
<!-- _paginate: false -->   # hide the page number on this slide
<!-- _footer: "" -->        # hide the footer on this slide
```

The generated theme ships two slide classes: `lead` (cover/closing slides)
and `divider` (section breaks). Use `lead` on the first slide.

## Images

```markdown
![w:300](image.png)             # width 300px (also h:, and w:300 h:200)
![bg](background.jpg)           # full-bleed background
![bg fit](diagram.png)          # background, contained
![bg right:40%](photo.jpg)      # split layout: image right 40%, text left
![bg left](photo.jpg)           # split layout: image left 50%
![bg opacity:.3](texture.jpg)   # washed-out background behind text
```

Multiple `![bg]` images on one slide tile side by side.

## Presenter notes

Any plain HTML comment (not a directive) becomes a presenter note —
included in PPTX speaker notes and HTML presenter view:

```markdown
<!-- Remember to mention the Q4 renewal numbers here. -->
```

## Content guidelines for decks that convert well

- One idea per slide; ≤ 6 bullets per slide; ≤ 12 words per bullet.
- Slides don't auto-overflow: content that doesn't fit is clipped.
  Split dense sections into multiple slides instead.
- Tables render at 0.85em — keep them ≤ 5 columns.
- Code blocks get the branded surface style; keep them ≤ 15 lines.
- Start with a `<!-- _class: lead -->` cover slide (title + subtitle),
  put an agenda slide second, and use `divider` slides between sections.
