# GEO — Generative Engine Optimization (référence LLM)

Optimiser pour les moteurs de réponse IA (ChatGPT, Perplexity, Claude, Gemini, Google AI Overviews). Distinct du SEO Google classique : l'objectif n'est pas le rang dans une SERP, c'est **être ingéré, compris et cité** par un LLM quand un utilisateur pose une question.

## Ordre de triage (du plus bloquant au plus fin)

1. **Accès des crawlers** — un site qui bloque les bots IA ne peut pas être cité. À vérifier en premier.
2. **`llms.txt`** — index markdown curé à la racine.
3. **Structured data (JSON-LD)** — les LLM extraient les faits du JSON-LD en priorité.
4. **Contenu extractible** — réponses affirmatives, Q/R, chiffres sourcés, entités nommées.
5. **Autorité externe** — citations, mentions, présence sur des sources que les modèles ingèrent.

## 1. Accès des crawlers IA (`app/robots.ts`)

Vérifier qu'aucun user-agent IA n'est en `disallow: "/"`. **C'est le piège le plus courant** : beaucoup de configs bloquent par défaut `GPTBot`/`CCBot` (réflexe « anti-scraping ») — ce qui rend le site invisible aux LLM.

Crawlers à connaître :

| User-agent | Acteur | Rôle | Bloquer le coupe de… |
|---|---|---|---|
| `GPTBot` | OpenAI | Entraînement | futurs modèles GPT |
| `OAI-SearchBot` | OpenAI | Index de recherche ChatGPT | résultats ChatGPT Search |
| `ChatGPT-User` | OpenAI | Navigation live | **citation en temps réel** dans ChatGPT |
| `ClaudeBot` | Anthropic | Entraînement | futurs modèles Claude |
| `Claude-User` / `Claude-SearchBot` | Anthropic | Navigation / index | citation dans Claude |
| `PerplexityBot` / `Perplexity-User` | Perplexity | Index / live | citation dans Perplexity |
| `Google-Extended` | Google | Gemini / Vertex | présence dans Gemini |
| `Applebot-Extended` | Apple | Apple Intelligence | présence Apple Intelligence |
| `CCBot` | Common Crawl | Dataset public | de nombreux modèles open + fermés |

**Deux politiques possibles** — c'est une décision business à confirmer avec le client :
- **Tout autoriser** (entraînement + retrieval) : visibilité maximale, y compris dans les futurs modèles. Le contenu nourrit l'entraînement sans contrepartie.
- **Retrieval seulement** : autoriser `*-User`, `*-SearchBot`, `PerplexityBot` (citation live) mais bloquer `GPTBot`, `CCBot`, `Google-Extended` (entraînement pur). Citable sans alimenter gratuitement l'entraînement.

Implémentation : voir `app/robots.ts` (constante `AI_CRAWLERS`).

## 2. `llms.txt` (`app/llms.txt/route.ts`)

Convention émergente (https://llmstxt.org/) : un fichier markdown à `/llms.txt` qui donne au LLM une vue curée et propre du site, sans le bruit du HTML/JS.

Structure attendue :

```markdown
# Nom du site

> Résumé en une phrase dense (qui, quoi, où, différenciateur).

## Section
- [Titre](URL absolue): description courte et factuelle
```

Règles :
- **H1** = nom de la marque, **blockquote** = pitch dense en une phrase.
- Liens **absolus** (`https://…`), jamais relatifs.
- Une ligne par ressource : `- [titre](url): description`.
- **Générer depuis les données du site** (produits, services, articles) via une route handler `force-static` — pas de fichier statique qui se désynchronise.
- Descriptions factuelles et affirmatives : c'est ce que le LLM citera.
- `Content-Type: text/plain; charset=utf-8`.
- Variante `llms-full.txt` possible : contenu complet inliné (pour les modèles qui ingèrent tout le texte). Optionnel.

## 3. JSON-LD orienté extraction (`components/JsonLd.tsx` (ou équivalent))

Les LLM s'appuient lourdement sur le structured data pour répondre factuellement. Au-delà des schémas classiques :
- **`Organization`** : ajouter `knowsAbout` (liste des domaines d'expertise — sert de carte d'entités au modèle), `slogan`, `sameAs` (profils sociaux = signaux d'autorité).
- **`FAQPage`** : chaque paire Q/R est une réponse prête à être citée. Maximiser la couverture FAQ sur les pages produits/services.
- **`Product` / `Service` / `Course`** : descriptions complètes, `provider`, `areaServed`, `offers`.
- Cohérence : les faits du JSON-LD doivent matcher le texte visible et le `llms.txt`. Une contradiction = perte de confiance du modèle.

## 4. Contenu extractible

- **Réponses affirmatives** en tête de section (« Donna est une assistante de direction IA qui… ») — pas d'intro marketing avant le fait.
- **Format Q/R** explicite : les questions matchent les prompts réels des utilisateurs.
- **Chiffres et faits sourcés**, entités nommées (lieux, technos, certifications) — extractibles et vérifiables.
- **Hiérarchie H1 > H2 > H3** propre : structure le découpage sémantique côté modèle.
- **Dates** visibles : les moteurs live privilégient le contenu récent.

## 5. Autorité externe (off-site)

Les LLM pondèrent fortement les sources qu'ils ont déjà ingérées : Wikipédia, presse, annuaires, LinkedIn, GitHub, Reddit. Plus déterminant pour le GEO que pour Google. Recommander : cohérence du NAP (nom/adresse/contact) cross-plateformes, présence sur les annuaires du secteur, mentions presse.

## Checklist GEO (pass/fail)

- [ ] `robots.ts` : aucun crawler IA en `disallow: "/"` involontaire ; politique (tout / retrieval) confirmée avec le client.
- [ ] `/llms.txt` servi en `text/plain`, généré depuis les données, liens absolus, accents UTF-8 corrects.
- [ ] `Organization` JSON-LD enrichi (`knowsAbout`, `slogan`, `sameAs`).
- [ ] `FAQPage` présent sur les pages clés (produits, services).
- [ ] Faits cohérents entre texte visible, JSON-LD et `llms.txt`.
- [ ] Réponses affirmatives en tête de section, format Q/R.
- [ ] Sitemap à jour (les crawlers IA le suivent aussi).

## Note langue

Tout texte français de ces livrables (llms.txt, descriptions JSON-LD, meta) DOIT respecter les conventions d'accents UTF-8 du projet (voir `CLAUDE.md` racine si une règle y est définie). Les champs meta/JSON-LD sont extraits verbatim par les LLM : un accent manquant s'y propage directement dans les réponses citées.
