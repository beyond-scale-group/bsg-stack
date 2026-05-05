#!/usr/bin/env python3
"""Aggregator for the md-to-office unit test suite.

Historical entry point used by CI and developers
(`python3 claude-skills/tests/test_md_to_office.py`). Split into topic
modules for #330:

  - test_md_to_office_resolve.py        — resolve-template.sh chain
  - test_md_to_office_orchestrator.py   — md-to-office.sh
  - test_md_to_office_scan.py           — scan-brand.py
  - test_md_to_office_init.py           — generate-templates.py + init-brand.sh
  - test_md_to_office_render.py         — render-docx.sh / render-pptx.sh / md parser
  - test_md_to_office_styling.py        — docx professional styling presets
  - _md_to_office_helpers.py            — shared script paths + run()

This shim imports every test class so unittest.main() discovers them when
the file is run directly. New tests should go in the topic module that
matches their concern, not here.

Run locally:

    python3 claude-skills/tests/test_md_to_office.py
"""

from __future__ import annotations

import os
import sys
import unittest

# Ensure sibling modules import whether the file is run directly or via
# `python3 -m unittest …` from the repo root.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from test_md_to_office_init import (  # noqa: E402,F401
    TestGenerateTemplatesPartialDeps,
    TestInitBrandSmoke,
)
from test_md_to_office_orchestrator import TestOrchestrator  # noqa: E402,F401
from test_md_to_office_render import (  # noqa: E402,F401
    TestMarkdownParser,
    TestRenderDocxSmoke,
    TestRenderPptxSmoke,
)
from test_md_to_office_resolve import TestResolveTemplate  # noqa: E402,F401
from test_md_to_office_scan import TestScanBrand  # noqa: E402,F401
from test_md_to_office_styling import (  # noqa: E402,F401
    TestGenerateDocxProfessionalStyling,
)


if __name__ == "__main__":
    unittest.main(verbosity=2)
