# Lexroom Analytics Engineer case: AMA quality

A small dbt project on DuckDB that models Lexroom's "Ask Me Anything" (AMA) data to answer three questions: quality per legal module (Product), account health risk (Customer Success) and a North Star for AMA quality (Leadership).

## Setup

```bash
conda create -n lexroom python=3.12 && conda activate lexroom   # or any virtualenv
pip install dbt-duckdb
export DBT_PROFILES_DIR=.        # profiles.yml is in the repo, DuckDB file is created locally
dbt build                        # 8 models, 29 tests (2 warn on purpose, see "Known data issues")
dbt docs generate && dbt docs serve
```

The raw CSVs are read in place from `data/` as dbt sources (`external_location`), so there is no seed step. On BigQuery the same sources would point to the Pub/Sub landing tables.

## Structure and grain

| Layer | Model | Grain (one row per...) |
|---|---|---|
| staging | `stg_ama_events` | AMA answer (deduplicated) |
| staging | `stg_ama_feedback` | feedback (deduplicated) |
| staging | `stg_users` | user |
| staging | `stg_workspaces` | workspace |
| intermediate | `int_ama_events_enriched` | AMA answer, with its feedback and workspace attributes |
| mart | `mart_ama_module_weekly` | legal module × week (Q1) |
| mart | `mart_workspace_health` | workspace, as of the last day with data (Q2) |
| mart | `mart_ama_quality_weekly` | week (Q3) |

Staging only cleans and renames; every business definition (what is a failure, what is a good answer) lives once in the intermediate model, so the three marts cannot disagree on them.

Weeks are ISO weeks (Monday start) in UTC. "Last 8 weeks" is anchored to the last week in the data (13 April 2026), not to today.

Answer queries are in [`analyses/`](analyses/); exposures in [`models/marts/exposures.yml`](models/marts/exposures.yml).

## Answers

### Q1: AMA quality trend per module

[`analyses/q1_ama_quality_by_module.sql`](analyses/q1_ama_quality_by_module.sql) gives the weekly trend; [`analyses/q1_module_focus.sql`](analyses/q1_module_focus.sql) compares the last 4 weeks with the 4 before.

| Module | Answers (last 4w) | Thumbs down (last 4w) | Thumbs-down rate (last 4w vs prev 4w) | Wrong or hallucinated |
|---|---|---|---|---|
| civile | 789 | 69 | 34% vs 24% | 32 |
| societario | 279 | 30 | 41% vs 26% | 17 |
| lavoro | 319 | 26 | 35% vs 28% | 10 |
| tributario | 191 | 19 | 38% vs 27% | 6 |
| penale | 163 | 15 | 27% vs 22% | 6 |
| amministrativo | 75 | 9 | 50% vs 32% | 6 |

Every module got worse from the week of 23 March. Where to focus:

1. **civile**: the largest volume of unhappy users (69 thumbs down, about 40% of all), +10 points.
2. **societario**: the sharpest deterioration on a meaningful volume (+15 points), and mostly *wrong answers / hallucinations*, i.e. a correctness problem, not a speed one.
3. amministrativo has the worst rate, but on 75 answers and fewer than 30 ratings per week: worth watching, not prioritising.

Timeouts and answers without sources stay around 1% all along, so the decline is about **answer content** (retrieval relevance or generation), not infrastructure. That points Product to the RAG / prompt side, not to latency work.

### Q2: account health risk

`risk_score` (0 to 100) compares each workspace's last 28 days with the 28 days before:

| Signal | Points | Why it matters |
|---|---|---|
| Quality drop: thumbs-down rate +10 points (min 5 rated) | 40 | Users are telling us directly the product got worse for them |
| Usage drop beyond the platform trend (min 10 answers) | 30 | Leading indicator of churn |
| Active users drop beyond the platform trend (min 3 users) | 20 | Adoption is shrinking inside the account |
| Failed answers ≥ 3% (timeouts or no sources, min 20 answers) | 10 | A technical issue CS can escalate, rarely a churn reason alone |

`high` ≥ 40, `medium` 20 to 39. Result: **9 high, 7 medium, 64 low.** The high list is led by 5 enterprise accounts (ws_0041, ws_0029, ws_0017, ws_0076, ws_0051) whose thumbs-down rate jumped, ws_0041 from 23% to 77%. Within the same score, the query sorts by previous volume, so CS calls the biggest accounts first.

**Why usage is relative to the platform:** AMA answers across the whole platform fell to about a third in the last 28 days, while active users fell only 13%. With absolute thresholds 36 of 80 workspaces were "high", which is not a list CS can act on. An account is flagged only if it declines clearly more than everyone else; the platform-wide decline is a separate finding (below).

### Q3: AMA North Star

**Good answer rate** = `technical_success_rate × (1 − thumbs_down_rate)`

- `technical_success_rate`: share of answers with no timeout and at least one retrieved source (measured on 100% of answers).
- `thumbs_down_rate`: thumbs down / rated answers (measured on the ~27% of answers that get rated).
- Grain: week. Window: last 8 complete weeks.

| Week | Answers | Good answer rate |
|---|---|---|
| 23 Feb | 1,714 | 0.71 |
| 2 Mar | 1,492 | 0.76 |
| 9 Mar | 1,180 | 0.76 |
| 16 Mar | 989 | 0.74 |
| 23 Mar | 840 | 0.66 |
| 30 Mar | 552 | 0.63 |
| 6 Apr | 322 | 0.65 |
| 13 Apr | 102 | 0.50 (low sample, 20 ratings) |

A clear step down from about 0.75 to about 0.65 from the week of 23 March.

**Why this formula.** My first version counted an answer as "good" if it had no technical failure and no thumbs down. It stayed flat at 0.90 to 0.93 while the thumbs-down rate went from 25% to 35%, because the 73% of unrated answers counted as good and diluted the signal. The estimated version keeps one number, still covers every answer, and moves with perceived quality. Its assumption (raters are representative of non-raters) is stated in the docs; `feedback_rate` is in the mart to monitor it.

**What I deliberately left out:** latency inside the North Star. Cached answers make it bimodal (~0.1 s vs ~3.2 s) and users rarely complain about it (7% of thumbs down are tagged `slow`). It stays as a diagnostic column, not a goal.

### The finding I would raise first

AMA volume fell from ~1,900 answers a week in mid-February to ~100 in mid-April, and active workspaces from 67 to 33, while quality dropped in the same weeks. Before anything else I would check with Engineering whether this is real (users leaving after worse answers) or an export/tracking artefact. If it is real, it is the most important number in this dataset.

## Known data issues and how they are handled

| Issue | Rows | Handling |
|---|---|---|
| Exact duplicate answers | 5 | Removed in staging (`SELECT DISTINCT`), `unique` test |
| Exact duplicate feedback | 15 | Removed in staging, `unique` test |
| `module_tag` in mixed case, plus `civil` for `civile` | ~250 | Lowercased and mapped, `accepted_values` test |
| Negative latency | 33 | Set to null, flagged `has_invalid_latency` |
| Latency of exactly 900,000 ms | 28 | Kept and flagged `is_timeout`: 83% of these are rated negative, so they are a real failure |
| `thumbs` of -2, 0, 2 | 16 | Set to null, excluded from quality metrics |
| Feedback on answers missing from the export | 50 | Kept in staging, dropped when joined to answers; `relationships` test set to **warn** |
| Answers from workspaces missing from `raw_workspaces` (ws_9000, ws_9001) | 8 | Kept for module metrics, excluded from the workspace mart; `relationships` test set to **warn** |
| Workspaces without country | 3 | `unknown` |
| Answers earlier than the user's `created_at` | 817 (71 users) | Documented as unreliable, not filtered |

The two warnings are intentional: they are known upstream issues that should be visible on every run without blocking it.

## Tests that matter

Beyond keys, accepted values and relationships, three singular tests:

- `assert_marts_reconcile_to_answers`: every answer is counted exactly once in both weekly marts. It protects every rate from fan-out in the feedback join or rows dropped by a filter.
- `assert_module_week_is_unique`: enforces the declared grain of the module mart.
- `assert_feedback_after_answer`: feedback cannot predate its answer; if it fails, the two event streams are out of sync and weekly attribution is wrong.

The `not_null` test on `risk_score` caught a real bug during development: workspaces with no recent activity got a null score instead of 0.

## Trade-offs

- **Unrated answers.** The North Star assumes raters are representative. Cheaper than modelling non-response, honest about its bias, and easy to replace later.
- **Thresholds and weights of the risk score are judgement calls**, chosen to be explainable to a CS lead in one sentence each. They should be calibrated against real churn as soon as we have it.
- **28-day windows vs ISO weeks.** The workspace mart uses rolling 28 days to smooth small accounts; the weekly marts use calendar weeks for readability. Different on purpose.
- **Views for staging and intermediate, tables for marts.** Fine at this size; on BigQuery the intermediate would become an incremental table partitioned by date.
- **UTC weeks.** Lexroom's users are in CET, so a few late-Sunday answers land in the next week. Negligible here; worth switching to `Europe/Rome` in production.

## What I would do next

1. Confirm the volume drop with Engineering (see above).
2. Calibrate the risk score against real churn or downgrade events, and add plan and seat data to weight accounts by revenue.
3. Add source freshness and row-count anomaly checks on the Pub/Sub landing tables.
4. Track `feedback_rate` per module: if it moves, the North Star is no longer comparable over time.
5. The optional engineering DORA mart (`raw_engineering_prs.csv`): I skipped it to stay within the time budget. The simplest useful metric would be weekly median lead time from PR open to merge, per team.

## How I used AI

I used Claude Code throughout: to profile the raw data with ad hoc DuckDB queries, scaffold the project, and draft SQL, YAML and documentation. The modelling and metric decisions are mine: grain of each mart, the North Star definition and its revision, the risk signals, weights and thresholds, and which data issues to fix, flag or tolerate. I reviewed every model and checked the numbers in this README against the marts.
