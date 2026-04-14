# render-adherence.jq — adherence.sh output → "Plan adherence" markdown.
# Bind root early so later `.` references inside each section don't
# accidentally descend into the intermediate joined strings.

. as $root
| if ($root.planFound | not) then
    "_No `po/PLAN.md` found in this repo. The agent can draft one — ask_ `@po-manager propose a starter PLAN`.\n\n_Until a plan exists, the sections below report raw activity only; there is no intent to compare against._"
  else
    # --- matrix ---
    (
      [
        "| Plan item | Bindings | Status | Evidence |",
        "| --- | --- | --- | --- |"
      ]
      + ($root.items | map(
          . as $it
          | (
              [ ($it.bindings.milestones // [] | map("milestone:\(.)"))[],
                ($it.bindings.epics      // [] | map("#\(.)"))[],
                ($it.bindings.labels     // [] | map("label:\(.)"))[]
              ] | join(", ") | if . == "" then "—" else . end
            ) as $binds
          | (
              [
                (if $it.counts.openIssues   > 0 then "\($it.counts.openIssues) open issue(s)"     else empty end),
                (if $it.counts.closedIssues > 0 then "\($it.counts.closedIssues) closed issue(s)" else empty end),
                (if $it.counts.openPrs      > 0 then "\($it.counts.openPrs) open PR(s)"           else empty end),
                (if $it.counts.mergedPrs    > 0 then "\($it.counts.mergedPrs) merged PR(s)"       else empty end),
                (if $it.counts.milestoneOpen   > 0 or $it.counts.milestoneClosed > 0
                   then "milestone: \($it.counts.milestoneClosed)/\($it.counts.milestoneOpen + $it.counts.milestoneClosed)"
                   else empty end)
              ] | join(", ") | if . == "" then "—" else . end
            ) as $ev
          | "| \($it.raw | gsub("\\|"; "\\\\|")) | \($binds) | **\($it.status)** | \($ev) |"
        ))
      | join("\n")
    ) as $matrix

    # --- summary ---
    | ($root.summary as $s
       | "- **\($s.totalPlanItems)** plan items: \($s.done) done · \($s.inProgress) in progress · \($s.atRisk) at-risk · \($s.notStarted) not-started\n- **\($s.scopeCreep)** unplanned open issues/PRs (scope creep)"
      ) as $summary

    # --- drift sections ---
    | (
        if (($root.drift.scopeCreep.issues | length) + ($root.drift.scopeCreep.pullRequests | length)) == 0 then ""
        else "\n\n### Scope creep — unplanned in-flight work\n\n"
          + (($root.drift.scopeCreep.issues + $root.drift.scopeCreep.pullRequests)
             | map("- [#\(.number)](\(.url)) — \(.title)")
             | join("\n"))
        end
      ) as $creep
    | (
        if ($root.drift.abandonedItems | length) == 0 then ""
        else "\n\n### Abandoned plan items (no GitHub activity)\n\n"
          + ($root.drift.abandonedItems | map("- \(.raw)") | join("\n"))
        end
      ) as $abandoned
    | (
        if ($root.drift.offCourse | length) == 0 then ""
        else "\n\n### Off-course plan items (milestone overdue, zero open work)\n\n"
          + ($root.drift.offCourse | map("- \(.raw)") | join("\n"))
        end
      ) as $offcourse

    | $matrix + "\n\n### Summary\n\n" + $summary + $creep + $abandoned + $offcourse
  end
