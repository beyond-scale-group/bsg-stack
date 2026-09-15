---
name: new-issue
description: >
  Guides a non-technical teammate through creating a well-formed GitHub issue
  for the dev team, on digischool-org/digischool.com for now. Asks the right
  questions depending on the request type (bug / feature / question /
  content), whether it's visual (front) or invisible (back), which site or
  the BO it concerns, and Figma link(s) when relevant, following the house
  Context/Request/Expected outcome style found in the repo's existing
  issues. Gathers what a dev needs to act on it, proposes an assignee when
  known or labels `needs-triage` when not, shows a draft for confirmation,
  then creates the issue with `gh issue create`. Use when the user asks to
  "créer un ticket", "ouvrir une issue pour les devs", "remonter un bug",
  "faire une demande de fonctionnalité", "new ticket for devs", "/new-issue".
model: sonnet
---

# New issue (pour non-devs)

Tu interviewes quelqu'un qui n'est pas développeur pour transformer sa
demande en une issue GitHub complète et actionnable par un dev, sans qu'il
ait à connaître le jargon technique. Sois chaleureux, pose une question à la
fois (ou regroupe via `AskUserQuestion` quand c'est naturel), et ne saute pas
d'étape même si la demande initiale semble déjà claire — un dev qui reçoit un
ticket incomplet perd du temps à revenir demander des infos.

**Repo cible (pour le moment) :** `digischool-org/digischool.com`. Ne
demande pas à l'utilisateur de choisir un repo — plus tard, quand plusieurs
projets seront couverts, c'est toi (Claude) qui devras déterminer le bon
repo à partir de la demande, jamais en posant la question à un non-dev.

## Process

### 0. Pré-requis

Vérifie que `gh auth status` est connecté. Si non, indique à l'utilisateur de
lancer `gh auth login` (interactif — à faire lui-même via `!`) et arrête-toi.

### 1. Spec déjà écrite ?

Avant toute question, demande en clair (pas besoin d'`AskUserQuestion`, une
question ouverte suffit ici) : "As-tu déjà écrit quelque chose sur cette
demande (description, notes, brief, ticket Jira, specs...) ? Tu peux me le
coller directement, je m'en servirai comme base."

- Si l'utilisateur colle du contenu → extrait tout ce que tu peux déjà en
  tirer (type de demande, contexte, besoin, résultat attendu, site/BO,
  lien(s) Figma, urgence...) et **ne repose pas** les questions des étapes
  suivantes pour ce qui est déjà répondu. Ne continue l'interview (étapes
  2-4) que pour les trous restants — dis explicitement ce que tu as déjà
  compris avant de demander la suite, pour que l'utilisateur puisse
  corriger si tu as mal interprété.
- Si l'utilisateur n'a rien d'écrit → passe normalement à l'étape 2.

### 2. Type de demande

Demande le type (si pas déjà déduit du texte collé à l'étape 1), ça
détermine les questions suivantes :
- **Bug** — quelque chose ne fonctionne pas
- **Amélioration / fonctionnalité** — un besoin, une idée
- **Question** — a besoin d'une réponse, pas forcément d'un dev
- **Contenu** — texte, image, wording à changer sur le site

### 3. Zone concernée (pour Bug et Amélioration/fonctionnalité)

Avant les questions détaillées, pose ces 2-3 questions courtes pour situer
la demande côté technique — utile même si l'utilisateur ne comprend pas la
distinction, les options doivent rester formulées simplement :

a) **Visuel ou invisible ?**
   "Est-ce quelque chose que tu peux voir à l'écran (un bouton, une page, un
   affichage...) ou un comportement qu'on ne voit pas directement (un
   calcul, un email envoyé, un traitement en arrière-plan...) ?"
   → détermine `front` (visuel) ou `back` (invisible).

b) **Site ou BO ?**
   "Ça concerne quel site (digischool.com, digischool.com_business,
   digischool.fr, mosalingua.com...) ou est-ce le BO (back-office /
   interface d'administration) ?"
   → note le site ou "BO" tel quel. Ça reste pour l'instant une information
   dans le ticket, pas un critère de routing : l'issue est créée dans
   `digischool-org/digischool.com` quel que soit le site concerné (voir
   note en haut de ce fichier — le multi-repo viendra plus tard).

c) **Lien(s) Figma** — uniquement si la réponse à (a) est "visuel/front"
   (le BO compte aussi comme du front, donc pose la question même si la
   réponse à (b) est "BO") :
   "As-tu un ou plusieurs liens Figma pour ça ?" Accepte zéro, un, ou
   plusieurs liens ; ne bloque pas si l'utilisateur n'en a pas.

Pour **Question** et **Contenu**, saute les points (a) et (c) — mais
demande quand même (b), quel site/BO est concerné, dans l'étape 4
ci-dessous.

### 4. Questions selon le type

**Bug :**
- Titre court du problème en une phrase
- Où ça se passe (page/URL précise, ou écran de l'app)
- Ce qui se passe actuellement vs. ce qui devrait se passer
- Étapes pour reproduire (le plus précis possible)
- Depuis quand / à quelle fréquence (tout le temps, parfois, une seule fois)
- Sur quel navigateur/appareil, et un compte utilisateur concerné si
  pertinent (email ou identifiant — jamais de mot de passe)
- A-t-il/elle une capture d'écran ou vidéo ? (lien Drive/Slack si oui —
  rappelle qu'iel pourra aussi glisser-déposer l'image directement dans
  l'issue GitHub une fois créée, ça marche mieux que dans le corps via API)
- Impact : combien de personnes touchées, est-ce bloquant pour quelqu'un

**Amélioration / fonctionnalité :**
- Contexte : quelle est la situation actuelle, quel problème ça pose
- Demande : ce qu'on voudrait voir fait, formulé comme une requête ("merci
  de faire X"), pas comme une solution technique imposée
- Résultat attendu : à quoi ça ressemble une fois fait, avec des critères
  concrets si possible (ex: "visible sur telle page", "seulement si le champ
  n'est pas vide")
- Pour qui (quels utilisateurs, quelle équipe)
- Deadline ou contrainte de date, et pourquoi

**Question :**
- Quel site/BO ça concerne (voir étape 3b)
- La question, formulée clairement
- Le contexte nécessaire pour y répondre

**Contenu :**
- Quel site/BO ça concerne (voir étape 3b)
- Quoi précisément (texte à changer, image à remplacer, etc.)
- Où exactement sur le site (page/URL)
- Le nouveau contenu, ou un lien vers le fichier/texte fourni

### 5. Assignation

Demande : "Sais-tu qui doit s'en occuper côté dev ?"
- Si oui → récupère le nom ou pseudo GitHub (demande le pseudo GitHub si
  seul le prénom est connu — cherche-le avec
  `gh api repos/digischool-org/digischool.com/assignees --paginate` si besoin
  de vérifier qu'il/elle existe bien comme assignable).
- Si non → ne mets **aucun** assignee. Le ticket recevra le label
  `needs-triage` (voir étape 6). Ne jamais assigner quelqu'un au hasard ou
  "deviner" un mapping zone→dev pour l'instant — cette automatisation
  viendra plus tard, et même alors elle ne fera que proposer, jamais
  assigner seule.

### 6. Construire le brouillon

Titre : concis, en anglais (comme les titres existants, ex: "Display
category descriptions on the Front Office"), orienté problème/besoin — pas
juste "Bug".

**Convention du repo (constatée sur les issues existantes, ex: #38, #39,
#40) : le corps est écrit en anglais avec des titres `###`, même si
l'interview avec le demandeur s'est faite en français.** Garde ce style —
c'est celui que les devs de ce repo connaissent.

**Gabarit de base (Bug et Amélioration/fonctionnalité) :**
```
### Context
<situation actuelle, pourquoi c'est un problème / un manque>

### Request
<ce qu'on demande, formulé comme une requête, pas une solution imposée>

### Expected outcome
<à quoi ressemble le résultat, en critères concrets>
- <critère 1>
- <critère 2>
```
Pour un **Bug**, remplace `Request`/`Expected outcome` par une structure
équivalente mais orientée réparation : `### Current behaviour`,
`### Expected behaviour`, `### Steps to reproduce`, `### Environment`,
`### Impact`.

Pour **Question** et **Contenu**, un gabarit plus court suffit (`### Context`
+ `### Request`), pas besoin de forcer les trois sections.

**Si un ou plusieurs liens Figma ont été donnés** (voir étape 3c), ajoute
simplement une ligne `Figma: <lien>` (ou une liste à puces si plusieurs)
dans le corps — pas de section dédiée, pas d'extraction automatique de la
maquette.

Termine toujours par une section `## Open points` (liste à puces) pour tout
ce qui reste incertain ou à confirmer avec une autre équipe (contenu
placeholder à remplacer, comportement mobile non couvert, ambiguïté avec un
autre élément déjà affiché, etc.) — reprends cet esprit de l'issue #40
plutôt que de laisser les devs découvrir ces zones grises en cours de dev.

Ajoute une ligne `_Ticket créé via /new-issue pour <nom de l'utilisateur>_`
tout en bas, après `## Open points`.

Labels à appliquer :
- Type : `bug`, `enhancement`, `question`, ou `content` (crée le label
  `content` s'il n'existe pas encore : `gh label create content --repo
  digischool-org/digischool.com --color BFD4F2 --description "Site content or copy change" --force`)
- `needs-triage` si aucun assignee n'a été donné (crée le label s'il
  n'existe pas : `gh label create needs-triage --repo
  digischool-org/digischool.com --color D93F0B --description "No assignee yet — needs a human to route it" --force`)

Ne touche pas aux labels de priorité (`P1`/`P2`/`P3`) ni aux labels `area:*`
— ce sont des conventions internes déjà utilisées pour autre chose, laisse
les devs les poser eux-mêmes. Si l'utilisateur a exprimé une urgence,
inclus-la en texte libre dans le corps du ticket plutôt qu'en label.

### 7. Confirmation

Affiche le brouillon complet (titre, corps, labels, assignee) et demande
confirmation explicite avant de créer quoi que ce soit sur GitHub. Propose
de corriger si besoin.

### 8. Création

Une fois confirmé :
```
gh issue create --repo digischool-org/digischool.com \
  --title "<titre>" --body "<corps>" \
  --label "<type>" [--label "needs-triage"] [--assignee "<login>"]
```

Donne l'URL de l'issue créée à l'utilisateur, et rappelle-lui qu'iel peut
encore glisser-déposer des captures d'écran directement dans l'issue sur
GitHub.

---

## How to improve this skill

This file is a cached copy of `claude-skills/skills/new-issue/SKILL.md` in
[beyond-scale-group/bsg-stack](https://github.com/beyond-scale-group/bsg-stack).
That repo is the single source of truth — `~/.claude/skills/new-issue/SKILL.md` is
overwritten every time the BSG install flow runs.

If the user asks you to improve, fix, or extend this skill, do **not** edit
the local file. Instead:

1. `gh repo clone beyond-scale-group/bsg-stack` (or work in an existing clone)
2. Edit `claude-skills/skills/new-issue/SKILL.md` on a feature branch
3. Open a pull request against `main`

Bug reports and ideas without a fix → open an issue on the same repo.
