# Voice / Tone Scoring

How the skill turns text into a single 0–10 "tone score."

## Inputs per asset

Computed in `collect.sh` for each asset (README, docs files,
landing pages, CHANGELOG, blog/):

| Signal                | Source                                                  |
| --------------------- | ------------------------------------------------------- |
| Word count            | `wc -w` after stripping markdown syntax                 |
| Sentence count        | Period/exclaim/question terminators                     |
| Avg sentence length   | words / sentences                                       |
| Passive-voice count   | regex for `(be|is|are|was|were|been) \w+ed` (heuristic) |
| Jargon matches        | grep against a static jargon list + bible banned terms  |
| Flesch reading ease   | `206.835 - 1.015 × (words/sentences) - 84.6 × (syllables/words)` |

Syllable count is a simple vowel-group heuristic; it's coarse but
stable across inputs.

## Tone score formula

The raw Flesch score ranges roughly from 0 (very difficult) to 100
(very easy). The skill maps it to a 0–10 tone scale:

```
baseScore = clamp(Flesch / 10, 0, 10)
penalty = 0.5 × passiveRatio + 0.5 × jargonDensity + 1.0 × bannedTermHits
toneScore = clamp(baseScore - penalty, 0, 10)
```

- `baseScore: 7` corresponds to Flesch ~70 (confident-casual). That
  matches the default bible target.
- Lower scores mean more formal / robotic / jargon-heavy.
- Higher scores mean very casual / simple.

## How to run

```bash
bash scripts/voice.sh                          # fresh
bash scripts/voice.sh --snapshot /tmp/*.json   # reuse snapshot
```

## Output schema

```json
{
  "summary": {
    "assetsScored": 12,
    "targetTone": 7.0,
    "meanScore": 6.3,
    "stddev": 1.4,
    "driftCount": 2
  },
  "perAsset": [
    { "file": "README.md", "toneScore": 7.2, "sentenceAvg": 14,
      "passiveRatio": 0.08, "jargonDensity": 0.05, "fleschEase": 72 }
  ],
  "drift": [
    { "file": "CHANGELOG.md", "toneScore": 3.0, "deviation": -2.35,
      "direction": "too formal / robotic" }
  ]
}
```

## How to interpret

- **`drift[]` non-empty** → silence-breaker. Each entry is an asset
  more than 2σ away from the bible target.
- **`summary.meanScore` trending away from target over multiple
  ticks** → not a silence-breaker, but surface in the narrative.
- **Large stddev (> 2)** → voice is inconsistent even on average;
  the bible's tone target may be too narrow for how the org
  actually writes. Flag for discussion.

## Caveats

- **Flesch is English-centric.** For non-English bibles, document
  the language and treat the absolute score with caution; deltas
  still matter.
- **CHANGELOG bullets are short by design.** A formal-leaning
  CHANGELOG may not be drift — it may be convention. The drift
  detector is directional; humans decide intent.
- **Passive voice is not always wrong.** "The database is backed
  up every six hours" is fine. The penalty is calibrated to
  discourage over-use, not ban passive outright.

## What NOT to do

- Don't rewrite drifting copy. Reporting only.
- Don't publish a tone score as a KPI — the score is a *relative*
  signal within this repo and bible context.
