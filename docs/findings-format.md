# Findings Input Format

The pipeline consumes **findings** — structured items describing issues, improvements, or changes to analyze and implement. Findings can come from any source: code analysis tools, draft specs, design reviews, bug reports, or manual entries.

The pipeline accepts any JSON input that matches the schema below.

---

## Input JSON schema

Place a JSON file at one of these locations (checked in order by `/run-pipeline`):
1. `~/Downloads/TechnicalVeil/` directory (legacy TV format)
2. `runs/findings_input.json` in the pipeline repo
3. `tv_output.json` in the target product repo

Or pass `--tv-input <path>` directly to `stage1-parse-findings.sh`:

```json
{
  "source": "your-tool-name",
  "findings": [
    {
      "id": "spec-001",
      "title": "Short title of the finding or draft spec",
      "description": "Detailed description of the issue, improvement, or spec. Max 500 chars used by the pipeline.",
      "source_url": "https://optional-link-to-source",
      "relevance_category": "api_change",
      "relevance_score": 0.8,
      "raw_data": {}
    }
  ]
}
```

## Required fields per finding

| Field | Type | Description |
|---|---|---|
| `id` | string | Unique identifier (used in branch names, file names, PR titles) |
| `title` | string | Short summary — becomes the PRD title |
| `description` | string | Detailed context — fed into Stage 2 impact analysis |
| `relevance_category` | string | Must match a key in `config/category_engine_map.json` |
| `relevance_score` | float | 0.0 – 1.0 relevance weight (filtered by `thresholds.json` minimum, default 0.5) |

## Optional fields

| Field | Type | Description |
|---|---|---|
| `source_url` | string | Link to the original source (included in PRs) |
| `raw_data` | object | Arbitrary metadata passed through to reports |

## Valid relevance categories

These are the default categories defined in `config/thresholds.json` and mapped to modules in `config/category_engine_map.json`:

`api_change` · `behavior_change` · `dependency_change` · `config_change` · `schema_change` · `performance_change` · `security_change`

Add or remove categories by editing both `thresholds.json` (stage_1.relevance_categories) and `category_engine_map.json` (mappings) — or edit the `thresholds` and `categories` sections in `pipeline.yml`.

## Using draft specs as findings

Findings don't have to come from a code analysis tool. You can use the pipeline to process **draft specs**, **RFCs**, or **improvement proposals**:

```json
{
  "source": "draft_specs",
  "findings": [
    {
      "id": "spec-auth-refresh",
      "title": "Add token refresh to authentication flow",
      "description": "The current auth flow requires full re-login when tokens expire. Add silent refresh using the refresh_token grant type. Must handle concurrent requests during refresh and queue them until the new token is available.",
      "relevance_category": "api_change",
      "relevance_score": 0.9
    }
  ]
}
```
