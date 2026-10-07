"""BSG shared-skills updater package.

Split out of the historical monolithic ``update-bsg-skills.py`` (#692) so
each responsibility lives in its own sub-500-LOC module. The public entry
point remains ``update-bsg-skills.py`` at the parent directory — that
bootstraps this package on first install then hands off to
``bsg_updater.core.run``.

Module map:

    config       — paths, constants, section table
    log_setup    — log file rotation + stdout redirection
    http_client  — GitHub Contents API GET + token discovery
    manifest     — load/save the .bsg-skills-manifest.json ownership file
    installer    — write a fetched blob to disk, honoring manifest ownership
    walker       — recursive walk over the Contents API
    reconcile    — orchestrate install + upstream-deletion for each section
    settings     — SessionStart hook registration + BSG-managed settings merge
    core         — run() — glue that stitches the modules together
"""
