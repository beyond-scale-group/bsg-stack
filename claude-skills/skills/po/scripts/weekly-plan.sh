#!/usr/bin/env bash
# weekly-plan.sh — turn the current snapshot into a Mon→Fri task plan,
# optionally write it into Google Calendar and re-assign GitHub issues.
#
# By default emits JSON on stdout (see references/weekly-plan.md for the
# shape). Flags:
#
#   --snapshot <path>       Reuse a collect.sh snapshot.
#   --start <YYYY-MM-DD|MON> First day. Default: next Monday from today.
#                           `MON` / `TUE` / ... resolves to the next
#                           occurrence of that weekday (today if it matches).
#   --slot <HH:MM-HH:MM>    Time slot for the calendar block. Default 08:30-08:45.
#   --timezone <TZ>         IANA tz, default `Europe/Paris`.
#   --report <path>         Markdown report to reference in event description.
#                           Default: po/reports/<today>-weekly-plan-s<isoweek>.md
#   --calendar              Create/patch one event per working day via gws.
#   --calendar-id <ID>      Calendar to write to. Default `primary`.
#   --assign                For each task, set assignee + milestone (dry-run).
#   --user <login>          Login used by --assign. Required if --assign.
#   --yes                   Actually mutate (otherwise --assign is dry-run).
#
# Exit codes:
#   0 = success
#   2 = usage error
#   3 = missing dependency (gh / jq / gws / python3)
#
# Notes:
# - Repo is resolved like collect.sh does: $GH_REPO env or `gh repo view`.
# - Idempotent calendar writes: existing events on the matching date whose
#   summary starts with `[<repo-short>] PO Daily — <day>` are patched
#   instead of duplicated.
# - --assign without --yes prints the would-be mutations to stderr.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"

# --- arg parsing ----------------------------------------------------------

snapshot_path=""
start_arg=""
slot="08:30-08:45"
timezone="Europe/Paris"
report_path=""
do_calendar=0
calendar_id="primary"
do_assign=0
assign_user=""
do_apply=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --snapshot) snapshot_path="$2"; shift 2 ;;
    --start) start_arg="$2"; shift 2 ;;
    --slot) slot="$2"; shift 2 ;;
    --timezone) timezone="$2"; shift 2 ;;
    --report) report_path="$2"; shift 2 ;;
    --calendar) do_calendar=1; shift ;;
    --calendar-id) calendar_id="$2"; shift 2 ;;
    --assign) do_assign=1; shift ;;
    --user) assign_user="$2"; shift 2 ;;
    --yes) do_apply=1; shift ;;
    -h|--help)
      sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "weekly-plan.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [[ $do_assign -eq 1 && -z "$assign_user" ]]; then
  echo "weekly-plan.sh: --assign requires --user <login>" >&2
  exit 2
fi

# --- deps -----------------------------------------------------------------

for bin in jq python3; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "weekly-plan.sh: $bin not found" >&2
    exit 3
  fi
done

# --- snapshot -------------------------------------------------------------

snapshot=""
if [[ -n "$snapshot_path" ]]; then
  snapshot=$(cat "$snapshot_path")
elif [[ ! -t 0 ]]; then
  snapshot=$(cat)
fi
if [[ -z "$snapshot" ]]; then
  if ! command -v gh >/dev/null 2>&1; then
    echo "weekly-plan.sh: gh not found and no snapshot provided" >&2
    exit 3
  fi
  snapshot=$(bash "$HERE/collect.sh")
fi

# --- build plan in python (cleaner than nested jq) ------------------------

snap_tmp=$(mktemp)
trap 'rm -f "$snap_tmp"' EXIT
printf '%s' "$snapshot" > "$snap_tmp"

plan_json=$(
  REPORT_PATH="$report_path" \
  START_ARG="$start_arg" \
  TODAY_ISO="$(date -u +%F)" \
  SNAPSHOT_PATH="$snap_tmp" \
  python3 - <<'PY'
import datetime as dt
import json
import os
import sys

with open(os.environ["SNAPSHOT_PATH"]) as f:
    snapshot = json.load(f)
start_arg = os.environ.get("START_ARG", "").strip()
report_path = os.environ.get("REPORT_PATH", "").strip()
today_iso = os.environ["TODAY_ISO"]
today = dt.date.fromisoformat(today_iso)

WEEKDAY_MAP = {"MON":0,"TUE":1,"WED":2,"THU":3,"FRI":4,"SAT":5,"SUN":6}

def next_weekday(d: dt.date, target: int) -> dt.date:
    delta = (target - d.weekday()) % 7
    if delta == 0:
        return d  # today matches target
    return d + dt.timedelta(days=delta)

if not start_arg:
    start = next_weekday(today, 0)
elif start_arg.upper() in WEEKDAY_MAP:
    start = next_weekday(today, WEEKDAY_MAP[start_arg.upper()])
else:
    try:
        start = dt.date.fromisoformat(start_arg)
    except ValueError:
        print(f"weekly-plan.sh: invalid --start value: {start_arg}", file=sys.stderr)
        sys.exit(2)

iso_year, iso_week, _ = start.isocalendar()
week_iso = f"{iso_year}-W{iso_week:02d}"

# Label uses the actual weekday so `--start FRI` produces "Ven … / Sam …",
# not "Lun …". We still emit exactly 5 days regardless of start.
WEEKDAY_FR = ["Lun","Mar","Mer","Jeu","Ven","Sam","Dim"]
days = []
for i in range(5):
    d = start + dt.timedelta(days=i)
    days.append({
        "date": d.isoformat(),
        "label": f"{WEEKDAY_FR[d.weekday()]} {d.day}/{d.month}",
        "index": i,
    })

repo = snapshot.get("repo", "")
repo_short = repo.split("/", 1)[1] if "/" in repo else repo
repo_url = f"https://github.com/{repo}" if repo else ""

if not report_path:
    report_path = f"po/reports/{today_iso}-weekly-plan-s{iso_week:02d}.md"

# --- classify issues ------------------------------------------------------

BLOCKER_LABELS = {"P0", "blocker", "urgent", "go"}
IN_PROGRESS_LABELS = {"in-progress", "wip"}
OUTREACH_LABELS = {"outreach", "cedant", "cédant"}
SPRINT_LABELS = {"P1", "epic", "sprint"}

def classify(issue: dict) -> str:
    labels = set(issue.get("labels") or [])
    if labels & BLOCKER_LABELS:
        return "A_blocker"
    if (issue.get("assignees") or []) or (labels & IN_PROGRESS_LABELS):
        return "B_in_progress"
    if labels & OUTREACH_LABELS:
        return "C_outreach"
    if labels & SPRINT_LABELS:
        return "D_sprint"
    return "Z_other"

# Target day indices per bucket (round-robin within those days).
TARGETS = {
    "A_blocker":     [0, 1],
    "B_in_progress": [1, 2],
    "C_outreach":    [2, 3],
    "D_sprint":      [2, 3],
    "Z_other":       [0, 1, 2, 3],
}

ACTIONS = {
    "A_blocker":     "débloquer",
    "B_in_progress": "avancer",
    "C_outreach":    "relancer",
    "D_sprint":      "avancer sprint",
    "Z_other":       "traiter",
}

THEMES = {
    "A_blocker":     "Débloquer P0 / urgences",
    "B_in_progress": "Push work in-progress",
    "C_outreach":    "Outreach cédants",
    "D_sprint":      "Avancer le sprint",
    "Z_other":       "Backlog / divers",
}

by_day: dict[int, list[dict]] = {i: [] for i in range(5)}
counters: dict[str, int] = {}

open_issues = [i for i in (snapshot.get("issues") or []) if i.get("state") == "OPEN"]

for issue in open_issues:
    bucket = classify(issue)
    targets = TARGETS[bucket]
    n = counters.get(bucket, 0)
    day_idx = targets[n % len(targets)]
    counters[bucket] = n + 1
    by_day[day_idx].append({
        "number": issue.get("number"),
        "title": issue.get("title", ""),
        "url": issue.get("url", ""),
        "labels": issue.get("labels") or [],
        "milestone": (issue.get("milestone") or {}).get("title") if issue.get("milestone") else None,
        "bucket": bucket,
        "kind": "issue",
    })

# PR review batch -> Friday (index 4).
prs = []
for pr in (snapshot.get("pullRequests") or []):
    if pr.get("state") != "OPEN":
        continue
    if pr.get("isDraft"):
        continue
    if pr.get("reviewDecision") == "APPROVED":
        continue
    prs.append({
        "number": pr.get("number"),
        "title": pr.get("title", ""),
        "url": pr.get("url", ""),
        "labels": pr.get("labels") or [],
        "bucket": "E_pr_review",
        "kind": "pr-review",
    })

by_day[4].extend(prs)

def theme_for(idx: int, tasks: list[dict]) -> str:
    if idx == 4 and any(t["kind"] == "pr-review" for t in tasks):
        return "PR review batch"
    if not tasks:
        return "Buffer / overflow"
    counts: dict[str, int] = {}
    for t in tasks:
        counts[t["bucket"]] = counts.get(t["bucket"], 0) + 1
    top = max(counts.items(), key=lambda kv: kv[1])[0]
    return THEMES.get(top, "Backlog / divers")

def priority_for(idx: int) -> str:
    if idx <= 1:
        return "P0"
    if idx == 4:
        return "PR-REVIEW"
    return "P1"

def task_action(t: dict) -> str:
    if t["kind"] == "pr-review":
        return f"review PR #{t['number']}"
    return ACTIONS.get(t["bucket"], "traiter")

plan = {
    "weekIso": week_iso,
    "repo": repo,
    "repoShort": repo_short,
    "repoUrl": repo_url,
    "reportPath": report_path,
    "days": [
        {
            "date": d["date"],
            "label": d["label"],
            "priority": priority_for(d["index"]),
            "theme": theme_for(d["index"], by_day[d["index"]]),
            "tasks": [
                {
                    "issue": t.get("number"),
                    "title": t.get("title", ""),
                    "url": t.get("url", ""),
                    "action": task_action(t),
                    "kind": t.get("kind", "issue"),
                }
                for t in by_day[d["index"]]
            ],
        }
        for d in days
    ],
}

json.dump(plan, sys.stdout, ensure_ascii=False, indent=2)
sys.stdout.write("\n")
PY
)

# --- emit JSON ------------------------------------------------------------

printf '%s\n' "$plan_json"

if [[ $do_calendar -eq 0 && $do_assign -eq 0 ]]; then
  exit 0
fi

# Pull a few values back out of the plan for side effects.
repo=$(jq -r '.repo' <<<"$plan_json")
repo_short=$(jq -r '.repoShort' <<<"$plan_json")
repo_url=$(jq -r '.repoUrl' <<<"$plan_json")
plan_report_path=$(jq -r '.reportPath' <<<"$plan_json")

# --- calendar -------------------------------------------------------------

if [[ $do_calendar -eq 1 ]]; then
  if ! command -v gws >/dev/null 2>&1; then
    echo "weekly-plan.sh: gws CLI not found — skipping --calendar" >&2
    exit 3
  fi

  start_hm="${slot%-*}"
  end_hm="${slot#*-}"
  if [[ ! "$start_hm" =~ ^[0-9]{2}:[0-9]{2}$ ]] || [[ ! "$end_hm" =~ ^[0-9]{2}:[0-9]{2}$ ]]; then
    echo "weekly-plan.sh: invalid --slot '$slot' (expected HH:MM-HH:MM)" >&2
    exit 2
  fi

  ndays=$(jq '.days | length' <<<"$plan_json")
  for i in $(seq 0 $((ndays - 1))); do
    day_json=$(jq -c ".days[$i]" <<<"$plan_json")
    date=$(jq -r '.date' <<<"$day_json")
    label=$(jq -r '.label' <<<"$day_json")
    theme=$(jq -r '.theme' <<<"$day_json")
    tasks_md=$(jq -r '.tasks
      | if length == 0 then "_(aucune tâche assignée)_"
        else map("- " + (
             if .issue then "#" + (.issue|tostring) + " — " + .title + " (" + .action + ")"
             else .title + " (" + .action + ")"
             end
           )) | join("\n")
      end' <<<"$day_json")

    # MANDATORY repo prefix in title + description (fix from issue #636).
    summary="[${repo_short}] PO Daily — ${label} : ${theme}"
    description=$(printf 'Repo: %s\nRéf: %s\n\nTâches:\n%s' \
      "$repo_url" "$plan_report_path" "$tasks_md")

    # Compute offset for the timezone via python (portable across mac/linux).
    offset=$(TZ_NAME="$timezone" DATE_STR="$date" HM="$start_hm" python3 - <<'PY'
import datetime as dt
import os
try:
    from zoneinfo import ZoneInfo
except ImportError:
    print("+00:00"); raise SystemExit(0)
tz_name = os.environ["TZ_NAME"]
date_str = os.environ["DATE_STR"]
h, m = (int(x) for x in os.environ["HM"].split(":"))
d = dt.date.fromisoformat(date_str)
local = dt.datetime(d.year, d.month, d.day, h, m, tzinfo=ZoneInfo(tz_name))
off = local.utcoffset() or dt.timedelta(0)
total = int(off.total_seconds())
sign = "+" if total >= 0 else "-"
total = abs(total)
print(f"{sign}{total//3600:02d}:{(total%3600)//60:02d}")
PY
)

    start_rfc="${date}T${start_hm}:00${offset}"
    end_rfc="${date}T${end_hm}:00${offset}"

    # Idempotency: look for an existing event the same day whose summary
    # starts with the repo-tagged prefix.
    time_min="${date}T00:00:00${offset}"
    time_max="${date}T23:59:59${offset}"
    existing_id=""
    existing_id=$(gws calendar events list --params "$(jq -nc \
        --arg cid "$calendar_id" --arg tmin "$time_min" --arg tmax "$time_max" \
        '{calendarId:$cid,timeMin:$tmin,timeMax:$tmax,singleEvents:true,orderBy:"startTime"}')" 2>/dev/null \
      | jq -r --arg prefix "[${repo_short}] PO Daily — ${label}" \
            '.items // [] | map(select(.summary | startswith($prefix))) | (.[0].id // "")' \
      2>/dev/null || true)

    if [[ -n "$existing_id" ]]; then
      echo "weekly-plan.sh: patch existing event ${existing_id} for ${date}" >&2
      gws calendar events patch \
        --params "$(jq -nc --arg cid "$calendar_id" --arg eid "$existing_id" \
                       '{calendarId:$cid,eventId:$eid}')" \
        --json "$(jq -nc \
                   --arg s "$summary" --arg d "$description" \
                   --arg start "$start_rfc" --arg end "$end_rfc" \
                   --arg tz "$timezone" \
                   '{summary:$s,description:$d,
                     start:{dateTime:$start,timeZone:$tz},
                     end:{dateTime:$end,timeZone:$tz}}')" >/dev/null
    else
      echo "weekly-plan.sh: insert new event for ${date}" >&2
      gws calendar +insert \
        --summary "$summary" \
        --start   "$start_rfc" \
        --end     "$end_rfc" \
        --description "$description" \
        --calendar "$calendar_id" >/dev/null
    fi
  done
fi

# --- assign ---------------------------------------------------------------

if [[ $do_assign -eq 1 ]]; then
  if ! command -v gh >/dev/null 2>&1; then
    echo "weekly-plan.sh: gh CLI not found — skipping --assign" >&2
    exit 3
  fi

  issues=$(jq -r '.days[].tasks[] | select(.kind == "issue" and .issue != null) | (.issue|tostring)' \
    <<<"$plan_json" | sort -u)

  for n in $issues; do
    current=$(printf '%s' "$snapshot" | jq -c --argjson n "$n" \
      '.issues[] | select(.number == $n)
       | {assignees: (.assignees // []),
          milestone: (.milestone.title // null)}')
    cur_assignees=$(jq -r '.assignees | join(",")' <<<"$current")

    needs_assignee=1
    if [[ -n "$cur_assignees" ]]; then
      case ",${cur_assignees}," in *",${assign_user},"*) needs_assignee=0 ;; esac
    fi

    if [[ $needs_assignee -eq 1 ]]; then
      if [[ $do_apply -eq 1 ]]; then
        echo "weekly-plan.sh: gh issue edit #${n} --add-assignee ${assign_user}" >&2
        gh issue edit "$n" --repo "$repo" --add-assignee "$assign_user" >/dev/null \
          || echo "weekly-plan.sh: failed to assign #${n}" >&2
      else
        echo "[dry-run] gh issue edit #${n} --add-assignee ${assign_user} (repo=${repo})" >&2
      fi
    fi
  done
fi
