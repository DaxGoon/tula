# Matra Code Quality Analysis

When asked to analyse code quality, run the matra analysis workflow.

## Workflow

1. Run `~/matra/scripts/detect.sh .` to identify project languages
2. For each detected language, run `~/matra/scripts/scan-<language>.sh --project-root .`
3. Run `~/matra/scripts/scan-docs.sh --project-root .`
4. Read rules from `~/matra/rules/_scoring.yml` and `~/matra/rules/<language>/*.yml`
5. Map tool findings to normalised severity (critical/high/medium/low) using
   the severity_map in each rule file
6. Calculate score: start at 1000, deduct severity_penalty * category_weight
   per issue
7. Report: overall score, category breakdown, top issues, recommendations

## Scoring Reference

- Categories: security (1.5x), reliability (1.2x), performance (1.0x),
  maintainability (0.8x), documentation (0.6x)
- Penalties: critical=-200, high=-100, medium=-25, low=-5
- Default pass threshold: 800/1000

## Project Overrides

Check for `.matra/overrides.yml` in the project root. If present, apply
disabled rules, severity overrides, and profile selection before scoring.
