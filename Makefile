# ============================================================================
# Pipeline Feedback System
# ============================================================================
#
# Full pipeline:    make pipeline-run | make pipeline-health-check
# Pipeline stages:  make pipeline-stage1 | make pipeline-prioritize | make pipeline-stage2 | make pipeline-stage3
#                   make pipeline-stage5 | make pipeline-stage7
#                   make pipeline-gates | make pipeline-stage11 | make pipeline-retry
#                   make pipeline-benchmark | make pipeline-stage13 | make pipeline-stage14
# Maintenance:      make update-engine-graph | make update-baselines | make pipeline-generate-baselines
# Scheduler:        make install-scheduler | make uninstall-scheduler
# Health:           make pipeline-health
#
# Prerequisites:
#   - Target product repo (set BUILDER_DIR or PIPELINE_BUILDER)
#   - Python 3.10+ (for scoring / benchmarks)
#   - jq (for JSON processing)
# ============================================================================

SHELL := /bin/bash
.DEFAULT_GOAL := help

# Paths
# BUILDER_DIR is required for local pipeline stages but NOT for docker-* targets.
# Docker targets get the builder dir via TARGET_REPO mount at /workspace/target.
BUILDER_DIR ?= $(PIPELINE_BUILDER)
CONFIG_DIR := config
SCRIPTS_DIR := scripts
RUNS_DIR := runs
LOGS_DIR := logs
BENCHMARKS_DIR := benchmarks
TV_DIR ?= $(HOME)/Downloads/TechnicalVeil

# Derive MODULES_DIR: check pipeline.yml first (via pipeline_preferences.json), fall back to project.json
ifneq (,$(wildcard $(CONFIG_DIR)/pipeline.yml))
MODULES_DIR := $(shell python3 -c "import yaml; print(yaml.safe_load(open('$(CONFIG_DIR)/pipeline.yml')).get('project',{}).get('modules_dir','packages'))" 2>/dev/null || echo "packages")
else
MODULES_DIR := $(shell python3 -c "import json; print(json.load(open('$(CONFIG_DIR)/project.json')).get('modules_dir', 'packages'))" 2>/dev/null || echo "packages")
endif
ifeq ($(MODULES_DIR),.)
PACKAGES_DIR := $(BUILDER_DIR)
else
PACKAGES_DIR := $(BUILDER_DIR)/$(MODULES_DIR)
endif

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
		--packages-dir $(PACKAGES_DIR) \
		--config $(CONFIG_DIR)/thresholds.json \
		--output $(RUNS_DIR)/$(RUN_TS) \
		2>&1 | tee $(LOGS_DIR)/stage2-$(RUN_TS).log

.PHONY: pipeline-stage3
pipeline-stage3: ## Run Stage 3: Integration design (Claude Code CLI)
	@mkdir -p $(RUNS_DIR)/$(RUN_TS) $(LOGS_DIR)
	@echo "Running Stage 3: Integration design..."
	@$(SCRIPTS_DIR)/stage3-integration-design.sh \
		--impact-dir $(RUNS_DIR)/$(RUN_TS) \
		--packages-dir $(PACKAGES_DIR) \
		--claude-md $(shell test -f $(BUILDER_DIR)/CLAUDE.md && echo $(BUILDER_DIR)/CLAUDE.md || echo /dev/null) \
		--output $(RUNS_DIR)/$(RUN_TS) \
		2>&1 | tee $(LOGS_DIR)/stage3-$(RUN_TS).log

.PHONY: pipeline-stage5
pipeline-stage5: ## Run Stage 5: PRD generation (dogfood via SKILL.md)
	@mkdir -p $(RUNS_DIR)/$(RUN_TS) $(LOGS_DIR)
	@echo "Running Stage 5: PRD generation (dogfood)..."
	@$(SCRIPTS_DIR)/stage5-prd-generation.sh \
		--run-dir $(RUNS_DIR)/$(RUN_TS) \
		--packages-dir $(PACKAGES_DIR) \
		--builder-dir $(BUILDER_DIR) \
		--engine-graph $(CONFIG_DIR)/engine_graph.json \
		--category-map $(CONFIG_DIR)/category_engine_map.json \
		--config $(CONFIG_DIR)/thresholds.json \
		--output $(RUNS_DIR)/$(RUN_TS) \
		2>&1 | tee $(LOGS_DIR)/stage5-$(RUN_TS).log

.PHONY: pipeline-stage7
pipeline-stage7: ## Run Stage 7: Implementation (Claude Code CLI on builder repo)
	@mkdir -p $(RUNS_DIR)/$(RUN_TS) $(LOGS_DIR)
	@echo "Running Stage 7: Implementation..."
	@$(SCRIPTS_DIR)/stage7-implementation.sh \
		--run-dir $(RUNS_DIR)/$(RUN_TS) \
		--builder-dir $(BUILDER_DIR) \
		--engine-graph $(CONFIG_DIR)/engine_graph.json \
		--config $(CONFIG_DIR)/thresholds.json \
		--output $(RUNS_DIR)/$(RUN_TS) \
		2>&1 | tee $(LOGS_DIR)/stage7-$(RUN_TS).log

.PHONY: pipeline-gates
pipeline-gates: ## Run Stage 10: Deterministic enforcement gates
	@mkdir -p $(RUNS_DIR)/$(RUN_TS) $(LOGS_DIR)
	@echo "Running Stage 10: Deterministic enforcement gates..."
	@$(SCRIPTS_DIR)/stage10-gates.sh \
		--builder-dir $(BUILDER_DIR) \
		--config $(CONFIG_DIR)/thresholds.json \
		--patterns $(CONFIG_DIR)/prohibited_patterns.txt \
		--output $(RUNS_DIR)/$(RUN_TS) \
		2>&1 | tee $(LOGS_DIR)/stage10-$(RUN_TS).log

.PHONY: pipeline-stage11
pipeline-stage11: ## Run Stage 11: Semantic verification (independent Claude session)
	@mkdir -p $(RUNS_DIR)/$(RUN_TS) $(LOGS_DIR)
	@echo "Running Stage 11: Semantic verification..."
	@$(SCRIPTS_DIR)/stage11-semantic-verification.sh \
		--run-dir $(RUNS_DIR)/$(RUN_TS) \
		--builder-dir $(BUILDER_DIR) \
		--engine-graph $(CONFIG_DIR)/engine_graph.json \
		--config $(CONFIG_DIR)/thresholds.json \
		--patterns $(CONFIG_DIR)/prohibited_patterns.txt \
		--finding-id $(FINDING_ID) \
		--branch $(BRANCH) \
		--output $(RUNS_DIR)/$(RUN_TS) \
		2>&1 | tee $(LOGS_DIR)/stage11-$(RUN_TS).log

.PHONY: pipeline-retry
pipeline-retry: ## Run retry orchestrator (Stage 7→10→11 loop per finding)
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
pipeline-benchmark: ## Run Stage 12: Quality benchmark comparison
	@mkdir -p $(RUNS_DIR)/$(RUN_TS) $(LOGS_DIR)
	@echo "Running Stage 12: Quality benchmark comparison..."
	@$(SCRIPTS_DIR)/stage12-benchmark.sh \
		--config $(CONFIG_DIR)/thresholds.json \
		--baselines $(BENCHMARKS_DIR)/baselines \
		--output $(RUNS_DIR)/$(RUN_TS) \
		2>&1 | tee $(LOGS_DIR)/stage12-$(RUN_TS).log

.PHONY: pipeline-stage13
pipeline-stage13: ## Run Stage 13: Deployment simulation (make distribute)
	@mkdir -p $(RUNS_DIR)/$(RUN_TS) $(LOGS_DIR)
	@echo "Running Stage 13: Deployment simulation..."
	@$(SCRIPTS_DIR)/stage13-deployment.sh \
		--builder-dir $(BUILDER_DIR) \
		--output $(RUNS_DIR)/$(RUN_TS) \
		2>&1 | tee $(LOGS_DIR)/stage13-$(RUN_TS).log

.PHONY: pipeline-stage14
pipeline-stage14: ## Run Stage 14: Pull request creation + staging sync
	@mkdir -p $(RUNS_DIR)/$(RUN_TS) $(LOGS_DIR)
	@echo "Running Stage 14: Pull request creation..."
	@$(SCRIPTS_DIR)/stage14-pull-request.sh \
		--run-dir $(RUNS_DIR)/$(RUN_TS) \
		--builder-dir $(BUILDER_DIR) \
		--engine-graph $(CONFIG_DIR)/engine_graph.json \
		--finding-id $(FINDING_ID) \
		--branch $(BRANCH) \
		--output $(RUNS_DIR)/$(RUN_TS) \
		2>&1 | tee $(LOGS_DIR)/stage14-$(RUN_TS).log

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
update-engine-graph: ## Regenerate engine dependency graph from package manifests + overrides
	@echo "Updating engine dependency graph..."
	@python3 $(SCRIPTS_DIR)/generate_engine_graph.py \
		--packages-dir $(PACKAGES_DIR) \
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
	@echo "Running Stage 12: Generate benchmark baselines..."
	@$(SCRIPTS_DIR)/stage12-benchmark.sh \
		--config $(CONFIG_DIR)/thresholds.json \
		--baselines $(BENCHMARKS_DIR)/baselines \
		--output $(RUNS_DIR)/$(RUN_TS) \
		--mode generate \
		2>&1 | tee $(LOGS_DIR)/stage12-generate-$(RUN_TS).log

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
	@python3 -c "import json; d=json.load(open('$(CONFIG_DIR)/engine_graph_overrides.json')); assert len(d['engines']) >= 1, f\"Expected >= 1 module, got {len(d['engines'])}\"" \
		&& echo "  engine_graph_overrides.json — $$(python3 -c "import json; print(len(json.load(open('$(CONFIG_DIR)/engine_graph_overrides.json'))['engines']))") modules OK" \
		|| { echo "  engine_graph_overrides.json — INVALID"; exit 1; }
	@echo ""
	@echo "Scripts validation:"
	@for script in stage2-impact-analysis.sh stage3-integration-design.sh stage5-prd-generation.sh stage6-prd-review.sh stage7-implementation.sh stage7-worker.sh stage7-reviewer.sh stage10-gates.sh stage11-semantic-verification.sh retry_orchestrator.sh stage12-benchmark.sh stage13-deployment.sh stage14-pull-request.sh update-baselines.sh health_check.sh pipeline.sh notify.sh; do \
		if [ -x "$(SCRIPTS_DIR)/$$script" ]; then \
			echo "  $$script — executable"; \
		else \
			echo "  $$script — MISSING or not executable"; \
			exit 1; \
		fi; \
	done
	@for pyfile in extract_prd_metrics.py prioritize_findings.py extract_contracts.py validate_impact_report.py validate_integration_plan.py generate_manifest.py compose_prd_input.py validate_prd_output.py compose_pr.py compose_improvement_report.py load_project_config.py decompose_work_units.py progress.py license.py; do \
		if [ -f "$(SCRIPTS_DIR)/$$pyfile" ]; then \
			echo "  $$pyfile — exists"; \
		else \
			echo "  $$pyfile — MISSING"; \
			exit 1; \
		fi; \
	done
	@echo ""
	@echo "Prompt templates:"
	@for tmpl in impact_analysis.md integration_design.md prd_generation.md prd_review.md implementation.md semantic_verification.md worker.md reviewer.md; do \
		if [ -f "prompts/$$tmpl" ]; then \
			echo "  $$tmpl — exists"; \
		else \
			echo "  $$tmpl — MISSING"; \
			exit 1; \
		fi; \
	done
	@echo ""
	@echo "Category-engine mapping:"
	@python3 -c "import json; d=json.load(open('$(CONFIG_DIR)/category_engine_map.json')); assert len(d['mappings']) >= 1, f\"Expected >= 1 mapping, got {len(d['mappings'])}\"" \
		&& echo "  category_engine_map.json — valid ($$(python3 -c "import json; print(len(json.load(open('$(CONFIG_DIR)/category_engine_map.json'))['mappings']))") mappings)" \
		|| { echo "  category_engine_map.json — INVALID"; exit 1; }
	@echo ""
	@echo "Benchmark inputs:"
	@INPUT_COUNT=$$(ls -1 $(BENCHMARKS_DIR)/inputs/*.json 2>/dev/null | wc -l | tr -d ' '); \
	if [ "$$INPUT_COUNT" -ge 1 ]; then \
		echo "  $$INPUT_COUNT benchmark inputs — OK (>= 1)"; \
	else \
		echo "  0 benchmark inputs — INSUFFICIENT (need >= 1)"; \
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
# Unified Config (pipeline.yml)
# ============================================================================

.PHONY: setup
setup: ## Interactive setup wizard — generates pipeline.yml
	@python3 $(SCRIPTS_DIR)/setup_wizard.py --builder-dir $(BUILDER_DIR)

.PHONY: resolve-config
resolve-config: ## Generate individual config files from pipeline.yml
	@python3 $(SCRIPTS_DIR)/resolve_config.py --config $(CONFIG_DIR)/pipeline.yml --output-dir $(CONFIG_DIR)

.PHONY: validate-config
validate-config: ## Validate pipeline.yml without generating files
	@python3 $(SCRIPTS_DIR)/resolve_config.py --config $(CONFIG_DIR)/pipeline.yml --validate

.PHONY: migrate-config
migrate-config: ## Migrate existing JSON/MD configs to pipeline.yml (one-time)
	@python3 $(SCRIPTS_DIR)/resolve_config.py --reverse --config $(CONFIG_DIR)/pipeline.yml --output-dir $(CONFIG_DIR)

# Auto-resolve: if pipeline.yml exists and is newer than sentinel, re-resolve
ifneq (,$(wildcard $(CONFIG_DIR)/pipeline.yml))
$(CONFIG_DIR)/.config_resolved: $(CONFIG_DIR)/pipeline.yml
	@echo "pipeline.yml changed — regenerating config files..."
	@python3 $(SCRIPTS_DIR)/resolve_config.py --config $(CONFIG_DIR)/pipeline.yml --output-dir $(CONFIG_DIR)

pipeline-run: $(CONFIG_DIR)/.config_resolved
pipeline-stage1: $(CONFIG_DIR)/.config_resolved
pipeline-stage2: $(CONFIG_DIR)/.config_resolved
pipeline-stage7: $(CONFIG_DIR)/.config_resolved
pipeline-stage14: $(CONFIG_DIR)/.config_resolved
pipeline-health: $(CONFIG_DIR)/.config_resolved
endif

# ============================================================================
# Progress
# ============================================================================

.PHONY: pipeline-progress
pipeline-progress: ## Show live pipeline progress for the latest run
	@python3 $(SCRIPTS_DIR)/progress.py --run-dir $$(ls -td $(RUNS_DIR)/*/ 2>/dev/null | head -1 || echo "$(RUNS_DIR)/LATEST") --watch

.PHONY: pipeline-status
pipeline-status: ## Show pipeline progress snapshot (no refresh)
	@python3 $(SCRIPTS_DIR)/progress.py --run-dir $$(ls -td $(RUNS_DIR)/*/ 2>/dev/null | head -1 || echo "$(RUNS_DIR)/LATEST")

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
# Docker
# ============================================================================

DOCKER_IMAGE := ai-architect-pipeline
DOCKER_TAG   := latest

# Auto-extract Claude Code OAuth access token from macOS Keychain.
# Passes just the accessToken string (not full JSON) — required by Claude CLI in Docker.
# If the token is stale, run `claude /login` first to refresh it.
CLAUDE_CODE_OAUTH_TOKEN ?= $(shell security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['claudeAiOauth']['accessToken'])" 2>/dev/null)
GH_TOKEN ?= $(shell gh auth token 2>/dev/null)

.PHONY: docker-build
docker-build: ## Build the Docker image with all dependencies
	docker build -t $(DOCKER_IMAGE):$(DOCKER_TAG) .

.PHONY: docker-run
docker-run: ## Run full pipeline in Docker (set TARGET_REPO)
	docker run --rm \
		-v $${TARGET_REPO:?Set TARGET_REPO to your product repo}:/workspace/target:ro \
		-v $$(pwd)/config:/app/config \
		-v $$(pwd)/runs:/app/runs \
		-v $$(pwd)/logs:/app/logs \
		-v $$HOME/.claude:/home/pipeline/.claude-host:ro \
		-v $$HOME/.claude.json:/home/pipeline/.claude-host-json/.claude.json:ro \
		-v $$HOME/.aiprd:/home/pipeline/.aiprd:ro \
		-e CLAUDE_CODE_OAUTH_TOKEN=$${CLAUDE_CODE_OAUTH_TOKEN:-} \
		-e GH_TOKEN=$${GH_TOKEN:-} \
		$(DOCKER_IMAGE):$(DOCKER_TAG)

.PHONY: docker-setup
docker-setup: ## Run interactive setup wizard in Docker
	docker run --rm -it \
		-v $${TARGET_REPO:?Set TARGET_REPO to your product repo}:/workspace/target:ro \
		-v $$(pwd)/config:/app/config \
		-v $$HOME/.aiprd:/home/pipeline/.aiprd:ro \
		$(DOCKER_IMAGE):$(DOCKER_TAG) setup

.PHONY: docker-health
docker-health: ## Run health check in Docker
	docker run --rm \
		-v $${TARGET_REPO:?Set TARGET_REPO to your product repo}:/workspace/target:ro \
		-v $$(pwd)/config:/app/config \
		-e GH_TOKEN=$${GH_TOKEN:-} \
		$(DOCKER_IMAGE):$(DOCKER_TAG) health

.PHONY: docker-shell
docker-shell: ## Open a shell inside the Docker container
	docker run --rm -it \
		-v $${TARGET_REPO:?Set TARGET_REPO to your product repo}:/workspace/target:ro \
		-v $$(pwd)/config:/app/config \
		-v $$(pwd)/runs:/app/runs \
		-v $$(pwd)/logs:/app/logs \
		-v $$HOME/.claude:/home/pipeline/.claude-host:ro \
		-v $$HOME/.claude.json:/home/pipeline/.claude-host-json/.claude.json:ro \
		-v $$HOME/.aiprd:/home/pipeline/.aiprd:ro \
		-e CLAUDE_CODE_OAUTH_TOKEN=$${CLAUDE_CODE_OAUTH_TOKEN:-} \
		-e GH_TOKEN=$${GH_TOKEN:-} \
		$(DOCKER_IMAGE):$(DOCKER_TAG) shell

# ============================================================================
# Help
# ============================================================================

.PHONY: help
help: ## Show this help
	@echo "Pipeline Feedback System"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-24s\033[0m %s\n", $$1, $$2}'
	@echo ""
