# Lexroom Analytics Engineer case: AMA quality

A small dbt project on DuckDB that models Lexroom's "Ask Me Anything" (AMA) data to answer three questions: quality per legal module (Product), account health risk (Customer Success) and a North Star for AMA quality (Leadership).

## Setup

```bash
conda create -n lexroom python=3.12 && conda activate lexroom   # or any virtualenv
pip install dbt-duckdb
export DBT_PROFILES_DIR=.        # profiles.yml is in the repo, DuckDB file is created locally
dbt build                        # 8 models, 33 tests (3 warn on purpose, see "Known data issues")
dbt docs generate && dbt docs serve
```

The raw CSVs are read in place from `data/` as dbt sources (`external_location`), so there is no seed step. The SQL uses DuckDB syntax (`FILTER`, `QUALIFY`, `MEDIAN`); moving to BigQuery would need small dialect changes.

## Structure and grain

| Layer | Model | Grain (one row per...) |
|---|---|---|
| staging | `stg_ama_events` | AMA answer (deduplicated on `event_id`) |
| staging | `stg_ama_feedback` | rated answer (latest rating wins) |
| staging | `stg_users` | user |
| staging | `stg_workspaces` | workspace |
| intermediate | `int_ama_events_enriched` | AMA answer, with its feedback and workspace attributes |
| mart | `mart_ama_module_weekly` | legal module × week (Q1) |
| mart | `mart_workspace_health` | workspace, as of `as_of_date` (Q2) |
| mart | `mart_ama_quality_weekly` | week (Q3) |

Staging cleans, renames and adds row-level flags (`is_timeout`, `has_no_sources`). The intermediate model combines them into the business definitions (`is_technical_success`, rated, thumbs down), so the three marts cannot disagree on them.

Weeks are ISO weeks (Monday start) in UTC. Everything is anchored to `as_of_date` = **12 April 2026** (a dbt var), not to today and not to the last row in the data: see "The data after 12 April" below.

Answer queries are in [`analyses/`](analyses/); exposures in [`models/marts/exposures.yml`](models/marts/exposures.yml).

## Answers

### Q1: AMA quality trend per module

[`analyses/q1_ama_quality_by_module.sql`](analyses/q1_ama_quality_by_module.sql) gives the weekly trend; [`analyses/q1_module_focus.sql`](analyses/q1_module_focus.sql) compares the last 4 complete weeks (16 Mar to 12 Apr) with the 4 before, next to the platform as a whole.

| Module | Answers (last 4w) | Rated | Thumbs down | Thumbs-down rate: prev 4w → last 4w | Change |
|---|---|---|---|---|---|
| **All modules** | 2,703 | 733 | 229 | 25.7% → 31.2% | +5.5 pts |
| civile | 1,156 | 304 | 88 | 25.9% → 28.9% | +3.0 |
| lavoro | 504 | 135 | 41 | 29.4% → 30.4% | +0.9 |
| societario | 421 | 112 | 40 | 25.1% → 35.7% | +10.6 |
| tributario | 263 | 65 | 23 | 25.6% → 35.4% | +9.8 |
| penale | 244 | 82 | 22 | 19.3% → 26.8% | +7.5 |
| amministrativo | 115 | 35 | 15 | 25.3% → 42.9% | +17.5 |

**The main finding is not a module, it is one platform-wide regression.** Starting the week of 23 March the thumbs-down rate of technically sound answers moves from 25.5% (16 Feb to 22 Mar, 1,923 ratings) to 34.5% (23 Mar to 12 Apr, 452 ratings), about 3.7 standard errors. It shows up across modules at roughly the same time, while timeouts and answers without sources stay around 1%. That points to a change in answer content (retrieval, prompt or model), not to infrastructure. The first thing I would do is ask Engineering what shipped around 23 March.

Where Product should focus:

1. **The regression itself**, across modules, before any module-specific work.
2. **civile** if one module must come first: it carries 38% of all thumbs down, so any fix there helps the most users.
3. societario, tributario and amministrativo move more than the platform, but with 35 to 112 ratings each the differences are within noise. Worth watching, not yet a decision.

Most module-weeks have fewer than 30 ratings (`is_low_sample`), so the weekly per-module trend is readable only as a direction; the 4-week comparison above is the version to decide on.

### Q2: account health risk

`risk_score` (0 to 100) compares each workspace's 28 days up to 12 April with the 28 days before:

| Signal | Points | Fires when | Why it matters |
|---|---|---|---|
| Quality drop | 40 | Thumbs-down rate ≥ 10 points higher, with ≥ 15 ratings in both periods | Users are telling us directly the product got worse for them |
| Usage drop | 30 | Answers below half of what the platform trend predicts for this workspace (≥ 30 answers before) | Leading indicator of churn |
| Users drop | 20 | Active users below half of what the platform trend predicts (≥ 5 users before) | Adoption is shrinking inside the account |
| Failed answers | 10 | ≥ 3% of answers timed out or had no sources (≥ 20 answers) | A technical issue CS can escalate, rarely a churn reason alone |

`high` ≥ 40, `medium` 20 to 39. The weights encode which single signal matters most: quality alone makes an account high, any other signal alone makes it medium.

Result: **6 high, 1 medium, 73 low.** All six high accounts fire on quality, five of them enterprise:

| Workspace | Plan | Answers prev → last 28d | Thumbs-down rate prev → last |
|---|---|---|---|
| ws_0041 | enterprise | 737 → 302 | 25% → 56% |
| ws_0036 | enterprise | 357 → 159 | 27% → 43% |
| ws_0074 | enterprise | 198 → 72 | 15% → 32% |
| ws_0033 | enterprise | 180 → 77 | 27% → 38% |
| ws_0071 | pro | 138 → 60 | 19% → 47% |
| ws_0051 | enterprise | 115 → 55 | 21% → 63% |

The one medium account, ws_0003 (pro), lost most of its usage (39 → 7 answers). The query sorts by score, then by previous volume, so CS calls the biggest accounts first.

**Why usage is relative to the platform.** Across the platform, answers in the last 28 days are 43% of the previous 28, while active users are 93%: people still log in but ask far fewer questions. My first version used absolute thresholds and small minimum volumes, and 36 of 80 workspaces came out high: not a list CS can act on. An account is flagged only if it declines clearly more than everyone else; the platform-wide decline is a Product and Leadership question, covered above.

**Known limits.** Thresholds and weights are judgement calls, chosen so each signal can be explained to a CS lead in one sentence; they should be calibrated against real churn. The list is sensitive to the window: moving `as_of_date` changes who crosses the 10-point line. Requiring the signal in two consecutive windows would make it more stable (see next steps).

### Q3: AMA North Star

**Good answer rate** = P(technically sound) × P(not rated down | technically sound)

```
good_answer_rate = technical_success_rate × (1 − thumbs_down_rate_successful)
```

- `technical_success_rate`: share of answers with no timeout and at least one retrieved source (measured on 100% of answers).
- `thumbs_down_rate_successful`: thumbs down / rated answers, among technically sound answers (measured on the ~27% of answers that get rated).
- Grain: week. Window: last 8 complete weeks up to 12 April.

| Week | Answers | Rated | Good answer rate |
|---|---|---|---|
| 16 Feb | 1,875 | 506 | 0.73 |
| 23 Feb | 1,714 | 448 | 0.71 |
| 2 Mar | 1,492 | 394 | 0.77 |
| 9 Mar | 1,180 | 317 | 0.77 |
| 16 Mar | 989 | 278 | 0.73 |
| 23 Mar | 840 | 229 | 0.66 |
| 30 Mar | 552 | 142 | 0.63 |
| 6 Apr | 322 | 84 | 0.65 |

A step down from about 0.75 to about 0.65 from the week of 23 March. Weekly values carry about ±0.04 of noise at 450 ratings and ±0.10 at 84, so the step is clear on the pooled weeks (see Q1) and should not be read week by week at the end of the series.

**Being honest about the formula.** Today the technical term is between 0.988 and 1.000 every week, so the North Star is essentially 1 − thumbs-down rate. I keep the technical term on purpose: it is the insurance that makes an infrastructure regression (timeouts, retrieval returning nothing) move the same number Leadership watches, without a second metric. If Leadership prefers, it can equally be shown as two numbers.

**Why the first version was dropped.** My first definition counted an answer as "good" when it had no technical failure and no thumbs down, over all answers. It stayed flat at 0.90 to 0.93 while the thumbs-down rate went from 25% to 35%, because the 73% of unrated answers counted as good and diluted the signal.

**The assumption, tested where possible.** The formula assumes that users who rate are representative of those who don't. On everything observable, rated and unrated answers look the same: median latency 2,946 vs 2,942 ms, median tokens 1,168 vs 1,172, median sources 5 vs 5, cached 14.9% vs 15.1%, no sources 0.7% vs 0.6%. The feedback rate is stable at 26 to 29% per week and 26 to 31% per module, and differs little by role. What cannot be ruled out is selection on satisfaction itself (unhappy users rating more often); `feedback_rate` is in the mart to monitor it.

**Left out on purpose:** latency. Cached answers make it bimodal (~0.1 s vs ~3.2 s) and only 7% of thumbs down are tagged `slow`. It stays as a diagnostic column.

### The data after 12 April

Until 12 April the decline is gradual (about 50 answers a day in early April). On Monday 13 April it drops in one step to about 15 a day and stays flat. That looks like a truncated export rather than real usage, so `as_of_date` stops on 12 April: the rows stay in the marts, flagged `is_after_as_of_date`, but no answer above depends on them.

The decline before that is still the first thing I would raise: AMA volume fell from ~1,900 answers a week in mid-February to ~320 in early April, in the same weeks quality dropped. Whether users are leaving after worse answers, or something else changed in tracking, is the most important open question in this dataset.

## Known data issues and how they are handled

| Issue | Rows | Handling |
|---|---|---|
| Duplicate answers (same `event_id`) | 5 | Latest row kept (`QUALIFY ROW_NUMBER()`), `unique` test |
| Duplicate feedback | 15 | One rating per answer, latest wins; `unique` test on `event_id` |
| `module_tag` in mixed case, plus `civil` for `civile` | 247 | Lowercased and mapped, `accepted_values` test |
| Negative latency | 33 | Set to null, flagged `has_invalid_latency` |
| Latency of exactly 900,000 ms | 28 | Kept and flagged `is_timeout`: 5 of the 6 rated were thumbs down |
| `thumbs` of -2, 0, 2 | 16 | Set to null, excluded from quality metrics |
| Feedback on answers missing from the export | 50 | Dropped when joined to answers; `relationships` test set to **warn**. They are 46% thumbs down vs 27% overall, so if the missing answers are failed generations, the thumbs-down rate is slightly understated |
| Answers from workspaces missing from `raw_workspaces` (ws_9000, ws_9001) | 8 | Kept for module metrics, excluded from the workspace mart; **warn** test |
| Users pointing to missing workspaces (u_orphan_0/1/2) | 3 | **warn** test |
| Workspaces without country | 3 | `unknown` |
| Answers earlier than the user's `created_at` | 817 (71 users) | Documented as unreliable, not filtered |
| Answers earlier than the workspace's `signup_date` | 597 (ws_0076: 511, ws_0019: 67, ws_0026: 19) | Flagged `is_before_workspace_signup`, not filtered; `signup_date` should not be used for tenure until fixed |
| Cached answers with odd values: 4 at the 900,000 ms timeout, 5 at exactly 45,000 ms, 12 with zero sources | 21 | Kept as recorded. The 12 count as technical failures, which may be wrong if cache hits log zero retrieval |
| Step change in volume on 13 April | 7 days | Excluded via `as_of_date` (see above) |

The three warnings are intentional: known upstream issues that should be visible on every run without blocking it.

## Tests that matter

Beyond keys, accepted values and relationships, four singular tests:

- `assert_marts_reconcile_to_answers`: every answer is counted exactly once in both weekly marts. Protects every rate from fan-out in the feedback join or rows dropped by a filter.
- `assert_rates_and_counts_in_range`: rates between 0 and 1, and thumbs down ≤ rated ≤ answers. Catches broken denominators and filters applied to one side only.
- `assert_reasons_reconcile_to_thumbs_down`: the reason columns (including `other` and `missing`) add up to the thumbs down, so a PM summing them gets the total.
- `assert_module_week_is_unique`: enforces the declared grain of the module mart.

`assert_feedback_after_answer` protects against the two event streams drifting out of sync; it cannot fire on this synthetic data (feedback always arrives within 10 minutes) but would in production.

The `not_null` test on `risk_score` caught a real bug during development: workspaces with no recent activity got a null score instead of 0.

## Trade-offs

- **Unrated answers.** The North Star assumes raters are representative; checked on observables, not on satisfaction itself.
- **Risk score thresholds and weights** are explainable rather than fitted, and should be calibrated on real churn.
- **28-day windows vs ISO weeks.** The workspace mart uses rolling 28 days to smooth small accounts; the weekly marts use calendar weeks for readability.
- **Views for staging and intermediate, tables for marts.** Fine at this size; in production the intermediate would become an incremental table partitioned by date.
- **UTC weeks.** Users are in CET, so about 1% of answers (late Sunday evening) land in a different week. Negligible here; worth switching to `Europe/Rome` in production.

## What I would do next

1. Ask Engineering what changed around 23 March, and whether the export after 12 April is complete.
2. Calibrate the risk score against real churn or downgrade events, require signals in two consecutive windows for stability, and weight accounts by revenue or seats.
3. Add confidence intervals (or a Wilson lower bound) to the weekly rates, so low-sample weeks are visible in the number and not only in a flag.
4. Add source freshness and row-count anomaly checks on the Pub/Sub landing tables; the 13 April step would have been caught on day one.
5. Track `feedback_rate` per module: if it moves, the North Star is no longer comparable over time.
6. The optional engineering DORA mart (`raw_engineering_prs.csv`): skipped to stay within the time budget. The simplest useful metric would be weekly median lead time from PR open to merge, per team.

## How I used AI

I used Claude Code throughout: to profile the raw data with ad hoc DuckDB queries, scaffold the project, and draft SQL, YAML and documentation. The modelling and metric decisions are mine: grain of each mart, the North Star definition and its revision, the risk signals, weights and thresholds, and which data issues to fix, flag or tolerate. I also had a second model review the finished project adversarially, recomputing the README numbers from the raw data; several fixes in this version (the North Star conditioning, the risk score volume minimums, the 12 April cut-off, the reason columns) came from that review. I reviewed every model and checked the numbers in this README against the marts.
