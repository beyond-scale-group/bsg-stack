---
name: transcript-to-devis
description: >
  Generate a complete commercial quote (devis) in Markdown from a raw
  sales-call transcript, following the standard The-Shift.ai devis
  structure. Extracts client, contact, project, scope, timeline, budget
  and validation milestones from the transcript, then produces a
  DEVIS_<CLIENT>_<PROJET>.md with the 10 standard sections, frontmatter,
  tarification grid and signature block. Use when the user asks to
  "génère un devis", "transforme ce transcript en devis", "devis à
  partir du call", "make a quote from this call", or pastes a sales
  call transcript and wants a proposal.
version: 0.1.0
tools: Read, Write, Bash
model: sonnet
output: chat
---

# Transcript → Devis

Turn a raw commercial-call transcript into a ready-to-send The-Shift.ai
quote in Markdown. The skill reads the transcript, extracts the
commercial facts, fills the standard 10-section devis template, and
writes the file to the customer repo (or locally as a fallback).

## Overview

The-Shift.ai quotes follow a fixed structure (deduced from
`DEVIS_MFA_CHATBOT_SAV_IA.md`): a YAML frontmatter block plus 10
numbered sections from *Contexte & livrable* to *Contacts + signature*.
This skill automates the boring 80%: it never invents commercial
commitments — anything not stated in the transcript is either left as
an explicit `À confirmer` placeholder or filled from the **reference
pricing** below, and the gaps are listed back to the user so a human
can validate before sending.

## Input

The transcript can arrive two ways:

1. **Inline** — pasted directly in the Discord/chat message after the
   invocation.
2. **File** — a path to a `.txt` / `.md` / `.vtt` transcript. Read it
   with the `Read` tool.

Expected transcript shape (tolerant — works with any of these):

- Raw dialogue with or without speaker labels
  (`Client:` / `The Shift:` / `[00:12] Jean -`).
- Meeting-notes style bullet points.
- A mix of French and English (output is **always French**).

Minimum viable transcript: enough to identify a client name and at
least one need/deliverable. If the client name is missing, ask the user
once before generating.

## Steps

1. **Acquire the transcript.** If a file path is given, `Read` it.
   Otherwise use the inline text. Reject empty input with a short ask.

2. **Extract commercial facts.** Parse the transcript for:
   - **Client** — company name → `client_slug` =
     lowercased, accents stripped, non-alnum → `-`.
   - **Contact** — interlocutor name + role + email/phone if stated.
   - **Projet** — short project label (e.g. "Chatbot SAV IA").
   - **Contexte** — 2–4 sentences: business problem + desired outcome.
   - **Architecture validée** — any tech/tools agreed on the call.
   - **Besoins → phases** — group needs into 2–5 phases; each phase
     becomes a row block: `Tâche / Responsable / Livrable`.
   - **Formation** — only if training was discussed.
   - **Délais** — any dates/durations → drives the weekly planning.
   - **Budget / TJH** — if the call mentions rates or a budget, use
     them; otherwise apply the **reference pricing** below.
   - **Infra tierce** — third-party costs mentioned (hosting, APIs…).
   - **ROI** — only if a quantifiable gain was stated.
   - **Jalons de validation** — explicit client validation points.

3. **Compute the pricing.** For each phase estimate jours-homme split
   Senior / Junior, multiply by the TJH, sum to a total HT, then
   `TTC = HT * 1.20` (TVA 20 %, FR). Never output a number that cannot
   be traced to a phase line. Round j-h to 0.5 day.

4. **Fill the template.** Substitute every `{{placeholder}}` in the
   *Template devis* section. Unknown but required fields →
   `À confirmer` (never silently invented). Skip optional sections
   (Formation §3, Infra §5, ROI §6) when the transcript has no signal —
   keep numbering contiguous by renumbering the remaining sections.

5. **Reference number.** `DEVIS-<CLIENT_UPPER>-<YYYY>-<NNN>`.
   `<YYYY>` = current year. `<NNN>` = `001` unless the user gives a
   sequence; if the customer repo is available, scan existing
   `commercial/` files and use `max+1` zero-padded to 3 digits.

6. **Write the output.** Target path (in priority order):
   - If `the-shift_ai-customers` repo is reachable:
     `the-shift_ai-customers/clients/<client_slug>/commercial/DEVIS_<CLIENT>_<PROJET>.md`
     (create the directory chain with `Bash mkdir -p`).
   - Else: write `./DEVIS_<CLIENT>_<PROJET>.md` locally **and** print
     the full Markdown back in chat so nothing is lost.

7. **Report back.** Print: the written path, the computed total HT/TTC,
   and a bullet list of every `À confirmer` gap the human must fill
   before sending. Never claim the quote is "final".

## Output

A single Markdown file `DEVIS_<CLIENT>_<PROJET>.md`:

- YAML frontmatter: `title`, `reference`, `date`, `client`, `contact`,
  `projet`, `validite`.
- 10 numbered sections (optional ones dropped + renumbered when empty).
- All amounts in € HT with the TTC recap and the 30/40/30 payment
  schedule.
- A signature block with two columns (The-Shift.ai / Client).

File naming: `<CLIENT>` and `<PROJET>` uppercased, accents stripped,
spaces → `_`. Example: `DEVIS_MFA_CHATBOT_SAV_IA.md`.

## Tarification de référence (The-Shift.ai)

Use these when the transcript does not state explicit rates:

| Profil | TJH standard | TJH après remise préférentielle |
| ------ | ------------ | ------------------------------- |
| Senior | 1 000 € HT/j | **900 € HT/j**                  |
| Junior | 600 € HT/j   | **500 € HT/j**                  |

Defaults & rules:

- Apply the **remise préférentielle** rates (900 / 500) by default —
  that is the standard commercial offer.
- TVA : **20 %** (`TTC = HT × 1,20`).
- Échéancier standard : **30 % à la signature / 40 % à mi-parcours /
  30 % à la livraison**.
- Validité de l'offre : **30 jours** sauf mention contraire.
- Garantie : **30 jours** de corrections post-livraison sur le
  périmètre validé.
- Estimate phases conservatively; if a phase is vague, mark its j-h as
  `À confirmer` rather than guessing a precise figure.

## Template devis

Render this template, substituting `{{...}}`. Drop optional sections
(§3 Formation, §5 Infrastructure, §6 ROI) when irrelevant and renumber
the following sections so numbering stays contiguous.

````markdown
---
title: "Devis — {{PROJET}}"
reference: "DEVIS-{{CLIENT_UPPER}}-{{YYYY}}-{{NNN}}"
date: "{{YYYY-MM-DD}}"
client: "{{CLIENT}}"
contact: "{{CONTACT_NOM}} — {{CONTACT_ROLE}} — {{CONTACT_EMAIL}}"
projet: "{{PROJET}}"
validite: "30 jours à compter du {{YYYY-MM-DD}}"
---

# Devis — {{PROJET}}

**Référence :** DEVIS-{{CLIENT_UPPER}}-{{YYYY}}-{{NNN}}
**Date :** {{DATE_FR}}
**Client :** {{CLIENT}}
**Contact :** {{CONTACT_NOM}} ({{CONTACT_ROLE}}) — {{CONTACT_EMAIL}}
**Émetteur :** The-Shift.ai

---

## 1. Contexte & livrable

**Objectif :** {{CONTEXTE_OBJECTIF}}

**Architecture validée :** {{ARCHITECTURE}}

**Outils :** {{OUTILS}}

**Livrable principal :** {{LIVRABLE_PRINCIPAL}}

---

## 2. Périmètre des prestations

{{#each PHASES}}
### Phase {{INDEX}} — {{PHASE_NOM}}

| Tâche | Responsable | Livrable |
| ----- | ----------- | -------- |
{{#each TACHES}}
| {{TACHE}} | {{RESPONSABLE}} | {{LIVRABLE}} |
{{/each}}

{{/each}}

---

## 3. Formation

| Module | Public | Durée | Format |
| ------ | ------ | ----- | ------ |
{{#each FORMATIONS}}
| {{MODULE}} | {{PUBLIC}} | {{DUREE}} | {{FORMAT}} |
{{/each}}

---

## 4. Tarification

**Taux journaliers (remise préférentielle incluse) :**

| Profil | TJH HT |
| ------ | ------ |
| Senior | {{TJH_SENIOR}} € |
| Junior | {{TJH_JUNIOR}} € |

**Détail par phase :**

| Phase | j-h Senior | j-h Junior | Total HT |
| ----- | ---------- | ---------- | -------- |
{{#each PHASES}}
| {{PHASE_NOM}} | {{JH_SENIOR}} | {{JH_JUNIOR}} | {{PHASE_TOTAL_HT}} € |
{{/each}}

**Récapitulatif :**

| | Montant |
| --- | --- |
| Total HT | **{{TOTAL_HT}} €** |
| TVA 20 % | {{TVA}} € |
| **Total TTC** | **{{TOTAL_TTC}} €** |

---

## 5. Infrastructure & coûts tiers

| Poste | Fournisseur | Coût estimé | À la charge de |
| ----- | ----------- | ----------- | -------------- |
{{#each INFRA}}
| {{POSTE}} | {{FOURNISSEUR}} | {{COUT}} | {{CHARGE}} |
{{/each}}

> Ces coûts tiers sont refacturés au réel ou pris en charge directement
> par le client selon l'accord ci-dessus.

---

## 6. ROI attendu

{{ROI_NARRATIF}}

| Indicateur | Avant | Après (cible) | Gain |
| ---------- | ----- | ------------- | ---- |
{{#each ROI_LIGNES}}
| {{INDICATEUR}} | {{AVANT}} | {{APRES}} | {{GAIN}} |
{{/each}}

---

## 7. Garanties & jalons de validation

- **Garantie :** 30 jours de corrections post-livraison sur le
  périmètre validé.
- **Jalons de validation client :**

| Jalon | Critère de validation | Responsable validation |
| ----- | --------------------- | ---------------------- |
{{#each JALONS}}
| {{JALON}} | {{CRITERE}} | {{VALIDATION_PAR}} |
{{/each}}

---

## 8. Conditions de paiement

| Échéance | % | Montant HT | Déclencheur |
| -------- | - | ---------- | ----------- |
| Signature | 30 % | {{ACOMPTE_30}} € | Signature du devis |
| Mi-parcours | 40 % | {{PAIEMENT_40}} € | {{JALON_MI_PARCOURS}} |
| Livraison | 30 % | {{SOLDE_30}} € | Recette finale |

- Règlement à 30 jours date de facture.
- Offre valable **30 jours** à compter du {{DATE_FR}}.

---

## 9. Planning prévisionnel

| Semaine | Phase | Activité principale | Livrable attendu |
| ------- | ----- | ------------------- | ---------------- |
{{#each PLANNING}}
| S{{SEMAINE}} | {{PHASE}} | {{ACTIVITE}} | {{LIVRABLE}} |
{{/each}}

**Durée totale estimée :** {{DUREE_TOTALE}}

---

## 10. Contacts & signature

**The-Shift.ai**
{{EMETTEUR_NOM}} — {{EMETTEUR_ROLE}}
{{EMETTEUR_EMAIL}}

**{{CLIENT}}**
{{CONTACT_NOM}} — {{CONTACT_ROLE}}
{{CONTACT_EMAIL}}

| Pour The-Shift.ai | Pour {{CLIENT}} |
| ----------------- | --------------- |
| Nom : | Nom : |
| Date : | Date : |
| Signature : | Signature : |

*Bon pour accord — précédé de la mention manuscrite « lu et approuvé ».*
````

## Hard rules

1. **Never invent commercial commitments.** Rates, scope, dates and ROI
   come from the transcript or the reference pricing — anything else is
   `À confirmer`.
2. **Always TVA 20 % and the 30/40/30 schedule** unless the transcript
   states otherwise.
3. **Output is always French**, even for an English transcript.
4. **Confirm before any external send.** The skill writes a file and
   reports; it never emails or shares the quote itself.
5. **List every `À confirmer` gap** in the final chat report so a human
   validates before the devis goes out.

## How to improve this skill

This file is a cached copy of
`claude-skills/skills/transcript-to-devis/SKILL.md` in
[beyond-scale-group/bsg-stack](https://github.com/beyond-scale-group/bsg-stack).
That repo is the single source of truth. To improve it, edit the file
on a feature branch in that repo and open a pull request against `main`
— do not edit the installed copy.
