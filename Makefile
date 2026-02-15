# ============================================================================
# ai-architect-feedback-loop — Pipeline Feedback System
# ============================================================================
#
# Pipeline stages:  make pipeline-stage1 | make pipeline-gates | make pipeline-benchmark
# Maintenance:      make update-engine-graph | make update-baselines
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

.PHONY: pipeline-benchmark
pipeline-benchmark: ## Run Stage 8: Quality benchmark comparison
	@mkdir -p $(RUNS_DIR)/$(RUN_TS) $(LOGS_DIR)
	@echo "Running Stage 8: Quality benchmark comparison..."
	@$(SCRIPTS_DIR)/stage8-benchmark.sh \
		--config $(CONFIG_DIR)/thresholds.json \
		--baselines $(BENCHMARKS_DIR)/baselines \
		--output $(RUNS_DIR)/$(RUN_TS) \
		2>&1 | tee $(LOGS_DIR)/stage8-$(RUN_TS).log

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

# ============================================================================
# Health / Validation
# ============================================================================

.PHONY: pipeline-health
pipeline-health: ## Validate config files and check prerequisites
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
