---
name: nextjs-seo
description: Next.js App Router SEO and GEO optimization guide. Use when asked to improve SEO, build Next.js apps, optimize for search engines, fix Google indexing, add sitemap.xml, implement metadata/meta tags, robots.txt, JSON-LD structured data, canonical URLs, Core Web Vitals, programmatic SEO (pages at scale), GEO (LLM/AI search — llms.txt, ChatGPT/Perplexity/Claude/Gemini citation), or audit SEO. Performs no visual redesigns.
---

# Next.js SEO Optimization

Comprehensive SEO guide for Next.js App Router applications.

## Scope

No visual redesigns or layout changes. Allowed: metadata, structured data, semantic HTML, internal links, alt text, sitemap/robots, GEO (llms.txt + AI crawlers), performance tuning.

## Workflow (audit & fix)

Copy and track this checklist, then work it in triage order — fix the most crawl-blocking issues first:

```text
SEO progress:
- [ ] Step 1: Inventory routes and index intent
- [ ] Step 2: Fix crawl/index foundations (robots, sitemap, noindex, canonicals, redirects, soft 404s)
- [ ] Step 3: Implement metadata + structured data
- [ ] Step 4: GEO — AI crawler access + llms.txt (see references/geo-llms.md)
- [ ] Step 5: Improve semantics, links, and Core Web Vitals
- [ ] Step 6: Validate with references/checklist.md and document changes
```

**Triage order when auditing:**
1. **Crawl/index** — robots, sitemap, noindex, canonicals, redirects, soft 404s
2. **GEO/LLM** — no AI crawler unintentionally blocked, `/llms.txt` present
3. **Technical** — HTTPS, Core Web Vitals, mobile parity
4. **On-page/content** — titles/H1, internal links, remove or noindex thin pages

## Quick SEO Audit

Run this checklist for any Next.js project:

1. **Check robots.txt**: `curl https://your-site.com/robots.txt`
2. **Check sitemap**: `curl https://your-site.com/sitemap.xml`
3. **Check metadata**: View page source, search for `<title>` and `<meta name="description">`
4. **Check JSON-LD**: View page source, search for `application/ld+json`
5. **Check Core Web Vitals**: Run Lighthouse in Chrome DevTools
6. **Check GEO (AI search)**: Verify no AI crawler is blocked in `robots.txt`, confirm `/llms.txt` exists — see [references/geo-llms.md](references/geo-llms.md)

## Essential Files

### app/layout.tsx - Root Metadata

```typescript
import type { Metadata, Viewport } from 'next';

// Viewport must be a separate export — `themeColor`, `colorScheme`, and
// `viewport` inside the `metadata` object are not supported.
export const viewport: Viewport = {
  width: 'device-width',
  initialScale: 1,
  maximumScale: 5,
  userScalable: true,
  themeColor: [
    { media: '(prefers-color-scheme: light)', color: '#ffffff' },
    { media: '(prefers-color-scheme: dark)', color: '#0a0a0a' },
  ],
};

export const metadata: Metadata = {
  metadataBase: new URL('https://your-site.com'),
  title: {
    default: 'Site Title - Main Keyword',
    template: '%s | Site Name',
  },
  description: 'Compelling description with keywords (150-160 chars; Google typically displays this range)',
  keywords: ['keyword1', 'keyword2', 'keyword3'],
  openGraph: {
    type: 'website',
    locale: 'en_US',
    url: 'https://your-site.com',
    siteName: 'Site Name',
    title: 'Site Title',
    description: 'Description for social sharing',
    images: [{ url: '/og-image.png', width: 1200, height: 630, alt: 'Site preview' }],
  },
  twitter: {
    card: 'summary_large_image',
    title: 'Site Title',
    description: 'Description for Twitter',
    images: ['/og-image.png'],
  },
  alternates: {
    canonical: '/',
  },
  robots: {
    index: true,
    follow: true,
  },
};
```

### app/sitemap.ts - Dynamic Sitemap

```typescript
import type { MetadataRoute } from 'next';

export default function sitemap(): MetadataRoute.Sitemap {
  const baseUrl = 'https://your-site.com';

  return [
    {
      url: baseUrl,
      lastModified: new Date(),
      changeFrequency: 'weekly',
      priority: 1,
      images: [`${baseUrl}/og-image.png`], // Image Sitemap entry
    },
    {
      url: `${baseUrl}/about`,
      lastModified: new Date(),
      changeFrequency: 'monthly',
      priority: 0.8,
    },
  ];
}
```

### app/robots.ts - Robots Configuration

```typescript
import type { MetadataRoute } from 'next';

export default function robots(): MetadataRoute.Robots {
  const baseUrl = 'https://your-site.com';

  return {
    rules: [
      {
        userAgent: '*',
        allow: '/',
        disallow: ['/api/', '/admin/'],
        // Do NOT disallow /_next/ — crawlers need render-critical CSS/JS
        // Do NOT add bot-specific rules (Googlebot, Bingbot) unless overriding wildcard
      },
    ],
    sitemap: `${baseUrl}/sitemap.xml`,
    host: baseUrl,
  };
}
```

## Key Principles

### Cache Components & SEO

With `cacheComponents: true` in next.config.ts, use the `"use cache"` directive for SEO-critical server components:

```typescript
// app/(home)/sections/hero-section.tsx
export async function HeroSection() {
  "use cache";
  cacheLife("minutes");   // Built-in profile: ~15 min
  cacheTag("hero");       // For targeted invalidation via revalidateTag("hero")

  const data = await fetchData();
  return <div>{/* SEO-visible content */}</div>;
}
```

**Key rules:**
- `"use cache"` must be the first statement in the function body
- No `cookies()`/`headers()` inside cache scope
- Use `cacheLife()` + `cacheTag()` instead of `export const revalidate`
- Sitemaps and metadata are static by default — only use `"use cache"` if they fetch dynamic data

### Rendering Strategy for SEO

| Strategy | Use When | SEO Impact |
|----------|----------|------------|
| "use cache" | Server components with periodic data | Best - cached HTML, fast TTFB |
| SSG (Static) | Content rarely changes | Best - pre-rendered HTML |
| SSR | Dynamic content per request | Great - server-rendered |
| CSR | Dashboards, authenticated areas | Poor - avoid for SEO pages |

### Core Web Vitals Targets

| Metric | Target | Impact |
|--------|--------|--------|
| LCP (Largest Contentful Paint) | < 2.5s | Loading speed |
| INP (Interaction to Next Paint) | < 200ms | Interactivity |
| CLS (Cumulative Layout Shift) | < 0.1 | Visual stability |

## Programmatic SEO (pages at scale)

When generating many pages from a repeatable pattern (product, location, glossary…):

- Validate demand for the pattern before generating pages
- Require **unique value per page** and defensible data — no boilerplate clones
- Clean subfolder URLs, hub/spoke structure, breadcrumbs
- Index only strong pages; monitor indexation and keyword cannibalization
- Never over-generate thin or doorway pages — indexation drops and quality signals suffer

## References

- **Metadata API**: See [references/metadata-api.md](references/metadata-api.md)
- **Sitemap & Robots**: See [references/sitemap-robots.md](references/sitemap-robots.md)
- **JSON-LD Structured Data**: See [references/json-ld.md](references/json-ld.md)
- **SEO Audit Checklist**: See [references/checklist.md](references/checklist.md)
- **Troubleshooting**: See [references/troubleshooting.md](references/troubleshooting.md)
- **GEO / LLM search (llms.txt, AI crawlers, citable content)**: See [references/geo-llms.md](references/geo-llms.md)

## Common Mistakes to Avoid

1. **Mixing next-seo with Metadata API** - Use only Metadata API in App Router
2. **Missing canonical URLs** - Always set `alternates.canonical`
3. **Using CSR for SEO pages** - Use SSG/SSR for indexable content
4. **Blocking `/_next/` in robots.txt** - Crawlers need render-critical CSS/JS; never disallow `/_next/`
5. **Missing metadataBase** - Required for relative URLs in metadata
6. **Viewport in metadata** - Must be a separate export
7. **Mixing metadata object and generateMetadata** - Use one or the other, not both
8. **JSON-LD that doesn't match visible content** - Google treats this as spam and may demote the page
9. **Changing URLs without 301 redirects** - Link equity and crawl budget are lost
10. **Conflicting canonicals across variants** - Trailing slash, www, uppercase splitting ranking signal
11. **Blocking AI crawlers unintentionally** - Disallowing GPTBot/ChatGPT-User/CCBot kills LLM citability (see references/geo-llms.md)

## Quick Fixes

### Add noindex to a page

```typescript
export const metadata: Metadata = {
  robots: {
    index: false,
    follow: false,
  },
};
```

### Dynamic metadata per page

```typescript
type Props = { params: Promise<{ id: string }> };

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { id } = await params;            // params is a Promise in current Next.js
  const product = await getProduct(id);
  return {
    title: product.name,
    description: product.description,
  };
}
```

### Canonical for dynamic routes

```typescript
type Props = { params: Promise<{ slug: string }> };

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { slug } = await params;
  return {
    alternates: {
      canonical: `/products/${slug}`,
    },
  };
}
```

---

## How to improve this skill

This file is a cached copy of `claude-skills/skills/nextjs-seo/SKILL.md` in
[beyond-scale-group/bsg-stack](https://github.com/beyond-scale-group/bsg-stack).
That repo is the single source of truth — `~/.claude/skills/nextjs-seo/SKILL.md` is
overwritten every time the BSG install flow runs.

If the user asks you to improve, fix, or extend this skill, do **not** edit
the local file. Instead:

1. `gh repo clone beyond-scale-group/bsg-stack` (or work in an existing clone)
2. Edit `claude-skills/skills/nextjs-seo/SKILL.md` on a feature branch
3. Open a pull request against `main`

Bug reports and ideas without a fix → open an issue on the same repo.
