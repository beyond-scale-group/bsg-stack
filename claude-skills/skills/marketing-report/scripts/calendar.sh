#!/usr/bin/env bash
# calendar.sh — classify calendar items.

set -euo pipefail

SNAPSHOT=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --snapshot) SNAPSHOT="$2"; shift 2 ;;
    *) shift ;;
  esac
done

if [[ -z "$SNAPSHOT" ]]; then
  SNAPSHOT=$(mktemp -t mkt-snap.XXXXXX.json)
  trap 'rm -f "$SNAPSHOT"' EXIT
  SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
  bash "$SCRIPT_DIR/collect.sh" > "$SNAPSHOT"
fi

jq '
  .calendar as $cal
  | if $cal.found == false then
      {
        calendarFound: false,
        summary: { total: 0, completed: 0, overdue: 0, today: 0, upcoming: 0 },
        overdueItems: [],
        todayItems: [],
        upcomingItems: []
      }
    else
      ($cal.items // []) as $items
      | [ $items[]
          | if .completed then {class: "completed"}
            elif .daysFromToday > 0 then {class: "overdue", daysLate: .daysFromToday}
            elif .daysFromToday == 0 then {class: "today"}
            else {class: "upcoming", daysUntil: (- .daysFromToday)} end
          | . + {date: ., title: .}   # placeholder — will be overwritten
        ] as $_unused
      | {
          calendarFound: true,
          summary: {
            total:     ($items | length),
            completed: ([$items[] | select(.completed)]                                           | length),
            overdue:   ([$items[] | select(.completed | not)  | select(.daysFromToday > 0)]     | length),
            today:     ([$items[] | select(.completed | not)  | select(.daysFromToday == 0)]    | length),
            upcoming:  ([$items[] | select(.completed | not)  | select(.daysFromToday < 0)]     | length)
          },
          overdueItems: [
            $items[] | select(.completed | not) | select(.daysFromToday > 0)
            | { date, title, daysLate: .daysFromToday }
          ],
          todayItems: [
            $items[] | select(.completed | not) | select(.daysFromToday == 0)
            | { date, title }
          ],
          upcomingItems: [
            $items[] | select(.completed | not) | select(.daysFromToday < 0)
            | { date, title, daysUntil: (- .daysFromToday) }
          ]
        }
    end
' "$SNAPSHOT"
