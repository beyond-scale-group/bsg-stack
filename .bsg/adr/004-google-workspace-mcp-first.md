# ADR-004: Architecture MCP-first pour Google Workspace, en remplacement de `gws`

- **Status:** Proposed
- **Date:** 2026-09-03
- **Resolves:** migration du skill `google-workspace`
- **Supersedes:** none

## Context

Le skill `claude-skills/skills/google-workspace` (4 268 lignes : `SKILL.md`,
7 fichiers de référence, 8 scripts) repose intégralement sur la CLI
`gws` (`googleworkspace/cli`, npm `@googleworkspace/cli`).

### Le fournisseur amont s'est arrêté

Constat vérifié via l'API GitHub et npm le 2026-09-03 :

| Signal | Valeur |
|---|---|
| Dernier commit sur `main` | `a3768d0`, **2026-03-31** |
| Dernière release | `v0.22.5`, 2026-03-31 |
| Dernier publish npm | 2026-03-31 |
| Issues ouvertes | 127 |
| Dépôt archivé ? | non |

Le dépôt n'est pas archivé et reçoit toujours des contributions — mais
elles sont **fermées sans merge** : #906 (executor 204), #908 et #909
(correctifs auth), #910 et #916 (sync skills), #915 (doc gmail), toutes
closes en août/septembre 2026. Cinq mois sans un seul merge sur `main`,
sur un produit encore en 0.x qui annonce des breaking changes.

Des bugs qui nous exposent sont ouverts sans perspective de correctif :
#876 (cache de token incohérent → 401 aléatoires), #886 (fichier de
credentials silencieusement supprimé si le déchiffrement échoue), #918
(scopes `cloud-platform` réinjectés après désélection), #911 (`+reply-all`
perd les CC), #861 (scopes insuffisants sur `calendar.events.list`),
#791 (la clé de chiffrement du keyring est écrite sur disque).

`gws 0.22.5` fonctionne aujourd'hui. Le risque n'est pas la panne
immédiate, c'est l'absence d'amont le jour où un flux OAuth casse.

### Google a déplacé son effort vers MCP

Google publie désormais huit serveurs MCP distants
(<https://developers.google.com/workspace/guides/configure-mcp-servers>,
Developer Preview). Interrogés en direct le 2026-09-03 avec un token issu
de notre propre client OAuth :

| Endpoint | Outils |
|---|---|
| `gmailmcp.googleapis.com/mcp/v1` | 23 |
| `calendarmcp.googleapis.com/mcp/v1` | 9 |
| `drivemcp.googleapis.com/mcp/v1` | 8 |
| `sheetsmcp.googleapis.com/mcp/v1` | 6 |
| `docsmcp` / `slidesmcp` | 2 / 2 |
| `chatmcp.googleapis.com/mcp/v1` | 4 |
| `people.googleapis.com/mcp/v1` | 3 |

`tasksmcp`, `formsmcp`, `keepmcp`, `meetmcp`, `adminmcp` n'existent pas.

Le gel de la CLI (31/03/2026) et l'arrivée des MCP coïncident. Aucune note
de dépréciation officielle n'a été publiée — l'inférence reste une
inférence, mais elle est cohérente avec le comportement observé.

### Les connecteurs Claude sont ces serveurs-là

Les connecteurs first-party disponibles en session Claude (`Gmail`,
`Google Calendar`, `Google Drive`) exposent des noms d'outils qui
coïncident au caractère près avec ceux de Google, y compris les plus
singuliers (`apply_sensitive_thread_label`, `respond_to_event`,
`suggest_time`) : Calendar 9/9, Drive 8/8, Gmail 23/23. Anthropic ajoute
par-dessus ce que Google n'expose pas — `send_message`, `reply`,
`forward`, `update_draft`, `share_file`.

### Ce que le MCP ne couvre pas

Relevé des usages réels du skill (grep sur `SKILL.md` + références +
scripts) confronté à la couverture MCP :

| Besoin | Occurrences | Chemin MCP |
|---|---|---|
| `gmail users.*` (brut) | 55 | partiel |
| `drive files.*` | 32 | oui |
| `gmail +send` | 18 | **connecteur Anthropic seulement** — le Gmail MCP de Google ne sait que `create_draft` |
| `calendar events` | 14 | oui |
| `sheets spreadsheets` | 11 | oui |
| `sheets +append` | 7 | **non** (pas de sémantique append) |
| `chat spaces` | 5 | oui |
| signatures / `settings.sendAs` | 3 scripts | **non** |
| `tasks`, `people contactGroups` | 3 | **non** pour Tasks |

S'y ajoute une contrainte structurelle : **un outil MCP n'est pas
appelable depuis bash**. Les 8 scripts du skill et tout usage cron ou
headless ont besoin d'un chemin API quel que soit le choix MCP.

### Le multi-compte est la contrainte dimensionnante

Nous opérons plusieurs comptes (personnel, Prizoners, clients) ;
`scripts/gws-switch.sh` les gère aujourd'hui par répertoire de config.

La documentation Claude Code est explicite : *« OAuth sign-ins are stored
per endpoint, not per server name »*. Déclarer le même serveur sous deux
noms leur fait partager le même token ; chaque bascule impose une
ré-authentification navigateur. Les connecteurs first-party sont pires
encore — un seul compte Google, lié au compte Claude.

Le mécanisme qui débloque : **`headersHelper`**, un script que Claude Code
exécute à chaque connexion (sans cache, 10 s de timeout, avec
`CLAUDE_CODE_MCP_SERVER_NAME` et `CLAUDE_CODE_MCP_SERVER_URL` en
environnement) pour produire les en-têtes d'authentification. Les serveurs
de Google acceptent un `Authorization: Bearer <access_token>` ordinaire —
vérifié : `initialize`, `tools/list` et `tools/call` répondent, le seul
refus étant « service non activé dans le projet ».

### La migration des identifiants est triviale

`gws auth export --unmasked` produit un JSON `authorized_user` standard
(`client_id`, `client_secret`, `refresh_token`) — le format ADC. Le client
OAuth est le nôtre, le consentement est déjà donné. Un bootstrap Python
stdlib de 15 lignes a atteint, sur le compte courant, Gmail (dont
`settings/sendAs`), Calendar, Drive, Tasks, Chat et People. **Aucune
reconsent ni démarche GCP n'est nécessaire pour changer de tuyau.**

## Decision

Le skill `google-workspace` cesse de traiter `gws` comme sa voie normale
et adopte une architecture à trois couches, routée par capacité.

### Couche 1 — Connecteurs Claude first-party (défaut interactif)

Gmail, Calendar, Drive. Zéro configuration, déjà actifs, et **seul chemin
MCP capable d'envoyer un email**. Voie par défaut en session interactive
pour la lecture, la recherche, le triage, l'agenda et les fichiers.

Limite assumée : un seul compte Google, celui du compte Claude. Dès que
le repo cible un autre compte, on descend en couche 2 ou 3.

### Couche 2 — Serveurs MCP Google, liés au repo via `headersHelper`

Sheets, Docs, Slides, Chat, People — et Gmail/Calendar/Drive quand le
compte visé n'est pas celui de la couche 1.

Déclaration en scope projet, dans le `.mcp.json` du repo consommateur :

```json
{
  "mcpServers": {
    "gws-sheets": {
      "type": "http",
      "url": "https://sheetsmcp.googleapis.com/mcp/v1",
      "headersHelper": "${CLAUDE_PROJECT_DIR}/.bsg/gws-auth-headers.sh"
    }
  }
}
```

Le helper (fourni par le skill, installé par `onboard.sh`) résout le
profil lié au repo, mint un access token depuis le refresh token de ce
profil, et émet `{"Authorization": "Bearer …"}`. **Aucun secret dans le
fichier versionné** — conforme à la politique du dépôt.

Prérequis one-shot par projet GCP : inscription au Developer Preview
Program et `gcloud services enable <svc>mcp.googleapis.com` pour chaque
service utilisé.

Limite assumée : le helper s'exécute à la connexion. Changer de compte en
cours de session demande de reconnecter le serveur via `/mcp` — ce n'est
pas une bascule par appel.

### Couche 3 — `scripts/gapi.py`, client stdlib

Pour tout ce qu'aucun MCP ne couvre et tout ce qui doit tourner hors
session Claude :

- envoi d'email et gestion des signatures / `sendAs` ;
- `sheets +append` ;
- Google Tasks ;
- les 8 scripts bash existants, le headless et le cron ;
- **le multi-compte par appel**, via `--profile`.

Contrat : Python stdlib uniquement (`urllib`), credentials au format
`authorized_user` par profil, appel générique
`gapi.py <service>.<resource>.<method> --params …` doublé des verbes
métier réellement utilisés. C'est le même patron que les skills
`email-imap` et `google-ads` du catalogue.

### `gws` rétrogradé en filet

Le binaire reste installé et fonctionnel pendant la transition, mais
disparaît de `SKILL.md` comme voie recommandée. Il est retiré quand la
parité est constatée sur les verbes du relevé ci-dessus.

### Routage de référence

| Capacité | Voie |
|---|---|
| Lire / chercher / trier des emails | couche 1 |
| Envoyer, répondre, transférer | couche 1 (interactif) · couche 3 (headless) |
| Signatures, `sendAs` | couche 3 |
| Agenda, événements | couche 1 |
| Drive : recherche, lecture, upload | couche 1 |
| Sheets : lecture, écriture | couche 2 |
| Sheets : append | couche 3 |
| Docs, Slides, Chat, People | couche 2 |
| Tasks, Forms, Keep, Meet | couche 3 |
| Compte ≠ compte Claude | couche 2 (par repo) · couche 3 (par appel) |
| Tout usage bash / cron / `claude -p` scripté | couche 3 |

## Consequences

**Ce qu'on gagne.** Le gros du volume passe sur du maintenu — Google pour
les serveurs, Anthropic pour les connecteurs. La surface que nous
maintenons tombe à un script d'auth et un client d'environ 250 lignes,
contre une dépendance à un binaire Rust abandonné. Le multi-compte
devient explicite et versionné par repo au lieu de dépendre d'un
répertoire de config global. Aucune reconsent OAuth n'est requise.

**Ce qu'on paie.** Trois chemins au lieu d'un : `SKILL.md` doit énoncer
une règle de routage claire, sinon l'agent choisira au hasard. Les MCP
Google sont en Developer Preview — surface instable, endpoints
susceptibles de bouger. Le `headersHelper` est un point de défaillance
propre à nous. Et nous devenons responsables de `gapi.py`, y compris de
ses régressions.

**Ce qui casse.** Les 8 scripts changent de socle. `gws-switch.sh` devient
un gestionnaire de profils de credentials plutôt qu'un commutateur de
répertoire de config. `doctor.sh` doit sonder trois couches au lieu d'une
CLI. Les 7 fichiers de référence, écrits en syntaxe `gws`, sont à
réécrire.

**Ce qu'on surveille.** Si Google promeut les MCP en GA et ajoute Tasks,
Forms et l'envoi Gmail, la couche 3 se réduit aux seuls besoins bash. Si
au contraire le Developer Preview stagne ou se ferme, la couche 3 absorbe
la couche 2 sans que la couche 1 bouge.

## Alternatives considered

**Statu quo, `gws` épinglé en 0.22.5.** Coût nul, couverture intacte. Mais
les bugs d'authentification connus (#876, #886) sont déjà là, sans
personne pour les corriger. Reporte le problème sans le traiter.

**Forker `googleworkspace/cli`.** Couverture intacte et contrôle total,
au prix d'un projet Rust à construire et distribuer sur plusieurs
plateformes, et de 127 issues héritées. Disproportionné pour la dizaine de
verbes que nous utilisons.

**Migrer vers GAM7** (`GAM-team/GAM`, 4 300 ⭐, poussé le 2026-09-03).
Réellement maintenu et très couvrant, mais orienté administration de
domaine : sa syntaxe et son modèle d'authentification conviennent aux
opérations d'admin en masse, pas à « envoie ce markdown par mail ».
Pertinent pour le futur skill `workspace-admin`, pas ici.

**Serveur communautaire unique** (`taylorwilsdon/google_workspace_mcp`,
3 112 ⭐, poussé le 2026-09-02) : 12 services, 120+ outils, OAuth 2.1
multi-utilisateur, impersonation par requête via service account, CLI
`workspace-cli` fournie, paliers `core`/`extended`/`complete` pour
contenir le contexte. C'est la seule alternative qui règle le multi-compte
*par appel* sans code de notre part. Écartée parce qu'elle substitue une
dépendance communautaire à de l'officiel sur la partie que Google couvre
déjà, et parce que 120+ outils pèsent lourd en contexte à chaque session.
**À réévaluer si la couche 3 dépasse la taille prévue** ou si le
Developer Preview se révèle instable.

**MCP seul, skill amputé.** Le plus léger à maintenir, mais abandonne
l'envoi en headless, les signatures, `sheets +append`, Tasks et tous les
scripts bash. Perte de capacités déjà acquises.

## References

- Serveurs MCP Google : <https://developers.google.com/workspace/guides/configure-mcp-servers>
- Authentification et scopes MCP dans Claude Code : <https://code.claude.com/docs/en/mcp>
- État amont de la CLI : <https://github.com/googleworkspace/cli> (`main` @ `a3768d0`, 2026-03-31)
- Alternative communautaire : <https://github.com/taylorwilsdon/google_workspace_mcp>
- Piste admin : <https://github.com/GAM-team/GAM>
