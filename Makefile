# ============================================================================
# ai-architect-feedback-loop — Pipeline Feedback System
# ============================================================================
#
# Full pipeline:    make pipeline-run | make pipeline-health-check
# Pipeline stages:  make pipeline-stage1 | make pipeline-prioritize | make pipeline-stage2 | make pipeline-stage3
#                   make pipeline-stage4 | make pipeline-stage5
#                   make pipeline-gates | make pipeline-stage7 | make pipeline-retry
#                   make pipeline-benchmark | make pipeline-stage9 | make pipeline-stage10
# Maintenance:      make update-engine-graph | make update-baselines | make pipeline-generate-baselines
# Scheduler:        make install-scheduler | make uninstall-scheduler
# Health:           make pipeline-health
#
# Prerequisites:
#   - Sibling project: ../ai-architect-prd-builder
#   - Python 3.10+ (for scoring / benchmarks)
#   - jq (for JSON processing)
# ============================================================================

SHELL := /bin/bash
.DEFAULT_GOAL := help

# Paths
BUILDER_DIR := ../ai-architect-prd-builder
CONFIG_DIR := config
SCRIPTS_DIR := scripts
RUNS_DIR := runs
LOGS_DIR := logs
BENCHMARKS_DIR := benchmarks
TV_DIR := $(HOME)/Downloads/TechnicalVeil

# Timestamp for pipeline runs
RUN_TS := $(shell date +%Y%m%d-%H%M%S)

# ============================================================================
# Pipeline Stages
# ============================================================================

.PHONY: pipeline-stage1
pipeline-stage1: ## Run Stage 1: Parse Technical Veil findings
	@mkdir -p $(RUNS_DIR)/$(RUN_TS) $(LOGS_DIR)
	@echo "Running Stage 1: Parse Technical Veil findings..."
	@$(SCRIPTS_DIR)/stage1-parse-findings.sh \
		--builder-dir $(BUILDER_DIR) \
		--config $(CONFIG_DIR)/thresholds.json \
		--tv-dir $(TV_DIR) \
		--output $(RUNS_DIR)/$(RUN_TS) \
		2>&1 | tee $(LOGS_DIR)/stage1-$(RUN_TS).log

.PHONY: pipeline-prioritize
pipeline-prioritize: ## Prioritize findings for Stage 2 (sort by impact, top-N)
	@mkdir -p $(RUNS_DIR)/$(RUN_TS) $(LOGS_DIR)
	@echo "Running prioritization: Rank findings by multi-engine impact..."
	@python3 $(SCRIPTS_DIR)/prioritize_findings.py \
		--findings $(RUNS_DIR)/$(RUN_TS)/findings.json \
		--category-map $(CONFIG_DIR)/category_engine_map.json \
		--engine-graph $(CONFIG_DIR)/engine_graph.json \
		--output $(RUNS_DIR)/$(RUN_TS)/prioritized_findings.json \
		--top-n 20 \
		2>&1 | tee $(LOGS_DIR)/prioritize-$(RUN_TS).log

.PHONY: pipeline-stage2
pipeline-stage2: ## Run Stage 2: Cross-engine impact analysis (Claude Code CLI)
	@mkdir -p $(RUNS_DIR)/$(RUN_TS) $(LOGS_DIR)
	@echo "Running Stage 2: Cross-engine impact analysis..."
	@$(SCRIPTS_DIR)/stage2-impact-analysis.sh \
		--findings $(RUNS_DIR)/$(RUN_TS)/prioritized_findings.json \
		--engine-graph $(CONFIG_DIR)/engine_graph.json \
		--category-map $(CONFIG_DIR)/category_engine_map.json \
		--packages-dir $(BUILDER_DIR)/packages \
		--config $(CONFIG_DIR)/thresholds.json \
		--output $(RUNS_DIR)/$(RUN_TS) \
		2>&1 | tee $(LOGS_DIR)/stage2-$(RUN_TS).log

.PHONY: pipeline-stage3
pipeline-stage3: ## Run Stage 3: Integration design (Claude Code CLI)
	@mkdir -p $(RUNS_DIR)/$(RUN_TS) $(LOGS_DIR)
	@echo "Running Stage 3: Integration design..."
	@$(SCRIPTS_DIR)/stage3-integration-design.sh \
		--impact-dir $(RUNS_DIR)/$(RUN_TS) \
		--packages-dir $(BUILDER_DIR)/packages \
		--claude-md $(BUILDER_DIR)/CLAUDE.md \
		--output $(RUNS_DIR)/$(RUN_TS) \
		2>&1 | tee $(LOGS_DIR)/stage3-$(RUN_TS).log

.PHONY: pipeline-stage4
pipeline-stage4: ## Run Stage 4: PRD generation (dogfood via SKILL.md)
	@mkdir -p $(RUNS_DIR)/$(RUN_TS) $(LOGS_DIR)
	@echo "Running Stage 4: PRD generation (dogfood)..."
	@$(SCRIPTS_DIR)/stage4-prd-generation.sh \
		--run-dir $(RUNS_DIR)/$(RUN_TS) \
		--packages-dir $(BUILDER_DIR)/packages \
		--builder-dir $(BUILDER_DIR) \
		--engine-graph $(CONFIG_DIR)/engine_graph.json \
		--category-map $(CONFIG_DIR)/category_engine_map.json \
		--config $(CONFIG_DIR)/thresholds.json \
		--output $(RUNS_DIR)/$(RUN_TS) \
		2>&1 | tee $(LOGS_DIR)/stage4-$(RUN_TS).log

.PHONY: pipeline-stage5
pipeline-stage5: ## Run Stage 5: Implementation (Claude Code CLI on builder repo)
	@mkdir -p $(RUNS_DIR)/$(RUN_TS) $(LOGS_DIR)
	@echo "Running Stage 5: Implementation..."
	@$(SCRIPTS_DIR)/stage5-implementation.sh \
		--run-dir $(RUNS_DIR)/$(RUN_TS) \
		--builder-dir $(BUILDER_DIR) \
		--engine-graph $(CONFIG_DIR)/engine_graph.json \
		--config $(CONFIG_DIR)/thresholds.json \
		--output $(RUNS_DIR)/$(RUN_TS) \
		2>&1 | tee $(LOGS_DIR)/stage5-$(RUN_TS).log

.PHONY: pipeline-gates
pipeline-gates: ## Run Stage 6: Deterministic enforcement gates
	@mkdir -p $(RUNS_DIR)/$(RUN_TS) $(LOGS_DIR)
	@echo "Running Stage 6: Deterministic enforcement gates..."
	@$(SCRIPTS_DIR)/stage6-gates.sh \
		--builder-dir $(BUILDER_DIR) \
		--config $(CONFIG_DIR)/thresholds.json \
		--patterns $(CONFIG_DIR)/prohibited_patterns.txt \
		--output $(RUNS_DIR)/$(RUN_TS) \
		2>&1 | tee $(LOGS_DIR)/stage6-$(RUN_TS).log

.PHONY: pipeline-stage7
pipeline-stage7: ## Run Stage 7: Semantic verification (independent Claude session)
	@mkdir -p $(RUNS_DIR)/$(RUN_TS) $(LOGS_DIR)
	@echo "Running Stage 7: Semantic verification..."
	@$(SCRIPTS_DIR)/stage7-semantic-verification.sh \
		--run-dir $(RUNS_DIR)/$(RUN_TS) \
		--builder-dir $(BUILDER_DIR) \
		--engine-graph $(CONFIG_DIR)/engine_graph.json \
		--config $(CONFIG_DIR)/thresholds.json \
		--patterns $(CONFIG_DIR)/prohibited_patterns.txt \
		--finding-id $(FINDING_ID) \
		--branch $(BRANCH) \
		--output $(RUNS_DIR)/$(RUN_TS) \
		2>&1 | tee $(LOGS_DIR)/stage7-$(RUN_TS).log

.PHONY: pipeline-retry
pipeline-retry: ## Run retry orchestrator (Stage 5→6→7 loop per finding)
	@mkdir -p $(RUNS_DIR)/$(RUN_TS) $(LOGS_DIR)
	@echo "Running retry orchestrator..."
	@$(SCRIPTS_DIR)/retry_orchestrator.sh \
		--run-dir $(RUNS_DIR)/$(RUN_TS) \
		--builder-dir $(BUILDER_DIR) \
		--engine-graph $(CONFIG_DIR)/engine_graph.json \
		--config $(CONFIG_DIR)/thresholds.json \
		--patterns $(CONFIG_DIR)/prohibited_patterns.txt \
		--finding-id $(FINDING_ID) \
		--output $(RUNS_DIR)/$(RUN_TS) \
		2>&1 | tee $(LOGS_DIR)/retry-$(RUN_TS).log

.PHONY: pipeline-benchmark
pipeline-benchmark: ## Run Stage 8: Quality benchmark comparison
	@mkdir -p $(RUNS_DIR)/$(RUN_TS) $(LOGS_DIR)
	@echo "Running Stage 8: Quality benchmark comparison..."
	@$(SCRIPTS_DIR)/stage8-benchmark.sh \
		--config $(CONFIG_DIR)/thresholds.json \
		--baselines $(BENCHMARKS_DIR)/baselines \
		--output $(RUNS_DIR)/$(RUN_TS) \
		2>&1 | tee $(LOGS_DIR)/stage8-$(RUN_TS).log

.PHONY: pipeline-stage9
pipeline-stage9: ## Run Stage 9: Deployment simulation (make distribute)
	@mkdir -p $(RUNS_DIR)/$(RUN_TS) $(LOGS_DIR)
	@echo "Running Stage 9: Deployment simulation..."
	@$(SCRIPTS_DIR)/stage9-deployment.sh \
		--builder-dir $(BUILDER_DIR) \
		--output $(RUNS_DIR)/$(RUN_TS) \
		2>&1 | tee $(LOGS_DIR)/stage9-$(RUN_TS).log

.PHONY: pipeline-stage10
pipeline-stage10: ## Run Stage 10: Pull request creation + staging sync
	@mkdir -p $(RUNS_DIR)/$(RUN_TS) $(LOGS_DIR)
	@echo "Running Stage 10: Pull request creation..."
	@$(SCRIPTS_DIR)/stage10-pull-request.sh \
		--run-dir $(RUNS_DIR)/$(RUN_TS) \
		--builder-dir $(BUILDER_DIR) \
		--engine-graph $(CONFIG_DIR)/engine_graph.json \
		--finding-id $(FINDING_ID) \
		--branch $(BRANCH) \
		--output $(RUNS_DIR)/$(RUN_TS) \
		2>&1 | tee $(LOGS_DIR)/stage10-$(RUN_TS).log

# ============================================================================
# Full Pipeline
# ============================================================================

.PHONY: pipeline-run
pipeline-run: ## Run full pipeline — nightly product improvement cycle
	@mkdir -p $(LOGS_DIR)
	@$(SCRIPTS_DIR)/pipeline.sh \
		--builder-dir $(BUILDER_DIR) --tv-dir $(TV_DIR)

.PHONY: pipeline-health-check
pipeline-health-check: ## Pre-flight: validate product + toolchain health
	@$(SCRIPTS_DIR)/health_check.sh --builder-dir $(BUILDER_DIR) \
		--config $(CONFIG_DIR)/thresholds.json

# ============================================================================
# Scheduler (launchd)
# ============================================================================

PLIST_LABEL := com.ai-architect.pipeline-feedback
PLIST_SRC := $(CONFIG_DIR)/$(PLIST_LABEL).plist
PLIST_DST := $(HOME)/Library/LaunchAgents/$(PLIST_LABEL).plist

.PHONY: install-scheduler
install-scheduler: ## Install nightly pipeline scheduler (launchd, 2 AM)
	@mkdir -p $(HOME)/Library/LaunchAgents $(LOGS_DIR)
	@sed 's|__REPO_DIR__|$(shell pwd)|g' $(PLIST_SRC) > $(PLIST_DST)
	@launchctl load $(PLIST_DST)
	@echo "Scheduler installed — pipeline runs nightly at 2 AM"

.PHONY: uninstall-scheduler
uninstall-scheduler: ## Remove nightly pipeline scheduler
	@launchctl unload $(PLIST_DST) 2>/dev/null || true
	@rm -f $(PLIST_DST)
	@echo "Scheduler removed."

# ============================================================================
# Maintenance
# ============================================================================

.PHONY: update-engine-graph
update-engine-graph: ## Regenerate engine dependency graph from Package.swift + overrides
	@echo "Updating engine dependency graph..."
	@python3 $(SCRIPTS_DIR)/generate_engine_graph.py \
		--packages-dir $(BUILDER_DIR)/packages \
		--overrides $(CONFIG_DIR)/engine_graph_overrides.json \
		--output $(CONFIG_DIR)/engine_graph.json

.PHONY: update-baselines
update-baselines: ## Update benchmark baselines from latest successful run
	@echo "Updating benchmark baselines..."
	@$(SCRIPTS_DIR)/update-baselines.sh \
		--runs-dir $(RUNS_DIR) \
		--output $(BENCHMARKS_DIR)/baselines

.PHONY: pipeline-generate-baselines
pipeline-generate-baselines: ## Generate benchmark baselines via PRD generation (slow)
	@mkdir -p $(RUNS_DIR)/$(RUN_TS) $(LOGS_DIR)
	@echo "Running Stage 8: Generate benchmark baselines..."
	@$(SCRIPTS_DIR)/stage8-benchmark.sh \
		--config $(CONFIG_DIR)/thresholds.json \
		--baselines $(BENCHMARKS_DIR)/baselines \
		--output $(RUNS_DIR)/$(RUN_TS) \
		--mode generate \
		2>&1 | tee $(LOGS_DIR)/stage8-generate-$(RUN_TS).log

# ============================================================================
# Health / Validation
# ============================================================================

.PHONY: pipeline-health
pipeline-health: ## Validate config files, scripts, and benchmarks
	@echo "Checking pipeline health..."
	@echo ""
	@echo "Builder project:"
	@if [ -d "$(BUILDER_DIR)" ]; then \
		echo "  $(BUILDER_DIR) — OK"; \
	else \
		echo "  $(BUILDER_DIR) — MISSING"; \
		exit 1; \
	fi
	@echo ""
	@echo "Config validation:"
	@python3 -c "import json; json.load(open('$(CONFIG_DIR)/thresholds.json'))" \
		&& echo "  thresholds.json — valid JSON" \
		|| { echo "  thresholds.json — INVALID"; exit 1; }
	@python3 -c "import re; [re.compile(l.strip()) for l in open('$(CONFIG_DIR)/prohibited_patterns.txt') if l.strip() and not l.startswith('#')]" \
		&& echo "  prohibited_patterns.txt — all valid regex" \
		|| { echo "  prohibited_patterns.txt — INVALID REGEX"; exit 1; }
	@python3 -c "import json; d=json.load(open('$(CONFIG_DIR)/engine_graph_overrides.json')); assert len(d['engines']) == 9, f\"Expected 9 engines, got {len(d['engines'])}\"" \
		&& echo "  engine_graph_overrides.json — 9 engines OK" \
		|| { echo "  engine_graph_overrides.json — INVALID"; exit 1; }
	@echo ""
	@echo "Scripts validation:"
	@for script in stage2-impact-analysis.sh stage3-integration-design.sh stage4-prd-generation.sh stage5-implementation.sh stage6-gates.sh stage7-semantic-verification.sh retry_orchestrator.sh stage8-benchmark.sh stage9-deployment.sh stage10-pull-request.sh update-baselines.sh health_check.sh pipeline.sh notify.sh; do \
		if [ -x "$(SCRIPTS_DIR)/$$script" ]; then \
			echo "  $$script — executable"; \
		else \
			echo "  $$script — MISSING or not executable"; \
			exit 1; \
		fi; \
	done
	@for pyfile in extract_prd_metrics.py prioritize_findings.py extract_contracts.py validate_impact_report.py validate_integration_plan.py generate_manifest.py compose_prd_input.py validate_prd_output.py compose_pr.py compose_improvement_report.py; do \
		if [ -f "$(SCRIPTS_DIR)/$$pyfile" ]; then \
			echo "  $$pyfile — exists"; \
		else \
			echo "  $$pyfile — MISSING"; \
			exit 1; \
		fi; \
	done
	@echo ""
	@echo "Prompt templates:"
	@for tmpl in impact_analysis.md integration_design.md prd_generation.md implementation.md semantic_verification.md; do \
		if [ -f "prompts/$$tmpl" ]; then \
			echo "  $$tmpl — exists"; \
		else \
			echo "  $$tmpl — MISSING"; \
			exit 1; \
		fi; \
	done
	@echo ""
	@echo "Category-engine mapping:"
	@python3 -c "import json; d=json.load(open('$(CONFIG_DIR)/category_engine_map.json')); assert len(d['mappings']) >= 10, f\"Expected >=10 mappings, got {len(d['mappings'])}\"" \
		&& echo "  category_engine_map.json — valid (>= 10 mappings)" \
		|| { echo "  category_engine_map.json — INVALID"; exit 1; }
	@echo ""
	@echo "Benchmark inputs:"
	@INPUT_COUNT=$$(ls -1 $(BENCHMARKS_DIR)/inputs/*.json 2>/dev/null | wc -l | tr -d ' '); \
	if [ "$$INPUT_COUNT" -ge 6 ]; then \
		echo "  $$INPUT_COUNT benchmark inputs — OK (>= 6)"; \
	else \
		echo "  $$INPUT_COUNT benchmark inputs — INSUFFICIENT (need >= 6)"; \
		exit 1; \
	fi
	@python3 -c "import json,sys,os;d='$(BENCHMARKS_DIR)/inputs';e=[f+': missing '+k for f in sorted(os.listdir(d)) if f.endswith('.json') for k in['context','title','description','requirements','expected']if k not in json.load(open(os.path.join(d,f)))];print('\n'.join('  '+x for x in e))or sys.exit(1)if e else print('  All inputs have required fields')" \
		|| { echo "  Benchmark input validation — FAILED"; exit 1; }
	@echo ""
	@echo "Benchmark baselines:"
	@BASELINE_COUNT=$$(ls -1d $(BENCHMARKS_DIR)/baselines/*/metrics.json 2>/dev/null | wc -l | tr -d ' '); \
	echo "  $$BASELINE_COUNT baselines with metrics.json"
	@echo ""
	@echo "Pipeline health: OK"

# ============================================================================
# Cleanup
# ============================================================================

.PHONY: clean
clean: ## Remove pipeline run artifacts and logs
	@echo "Cleaning pipeline artifacts..."
	@rm -rf $(RUNS_DIR)/*
	@rm -rf $(LOGS_DIR)/*
	@echo "Clean complete."

# ============================================================================
# Help
# ============================================================================

.PHONY: help
help: ## Show this help
	@echo "ai-architect-feedback-loop — Pipeline Feedback System"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-24s\033[0m %s\n", $$1, $$2}'
	@echo ""
