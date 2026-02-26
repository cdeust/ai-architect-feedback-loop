# AI Architect Feedback Loop — Architecture

## Overview
A 14-stage autonomous product improvement pipeline for Claude Code.
Stages 4, 8, 9 are Apple Intelligence only (skipped in CLI/Docker).

## Module Structure
- **scripts/** — Stage scripts (stage1 through stage14), validators, utilities
- **config/** — Pipeline configuration (pipeline.yml, thresholds, engine graph)
- **prompts/** — AI prompt templates for each stage
- **.claude/commands/** — Slash command definitions (/run-pipeline)

## Key Patterns
- Shell scripts orchestrate stages; Python scripts handle validation/analysis
- artifact_paths.sh provides standardized artifact resolution with backward compat
- retry_orchestrator.sh cycles implementation→gates→verification (stages 7→10→11)
- resolve_config.py generates individual config files from unified pipeline.yml

## Constraints
- All shell scripts use `set -euo pipefail` and structured JSON logging
- Python scripts use stdlib only (no pip dependencies except PyYAML for config)
- Prohibited patterns (TODO, FIXME, HACK, etc.) enforced by stage 10 gates
