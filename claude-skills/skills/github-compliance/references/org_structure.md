# Beyond Scale Group — GitHub Org Structure

## Organisation

- **GitHub org:** `beyond-scale-group`
- **URL:** https://github.com/beyond-scale-group

## Teams

| Team | Slug | Permission | Usage |
|---|---|---|---|
| board | `board` | admin | Accès admin à tous les repos privés actifs |
| outside_collaborator | `outside_collaborator` | pull | Collaborateurs externes |

## Règle de conformité

Tout repo **privé** et **non-archivé** doit être assigné à la team `board`
avec permission `admin`.

## Repo public (ignoré)

`prompt-eng-interactive-tutorial`

## Maintenance

The list of active and archived repos is intentionally not duplicated
here — it changes as the org evolves. Run
`bash ~/.claude/skills/github-compliance/scripts/check_compliance.sh` to
get the current snapshot from the GitHub API directly.
