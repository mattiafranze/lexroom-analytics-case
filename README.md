# Lexroom Analytics Engineer case: AMA quality

A small dbt project on DuckDB that models Lexroom's "Ask Me Anything" (AMA) data to answer three questions: quality per legal module (Product), account health risk (Customer Success) and a North Star for AMA quality (Leadership).

## Setup

```bash
conda create -n lexroom python=3.12 && conda activate lexroom   # or any virtualenv
pip install dbt-duckdb
export DBT_PROFILES_DIR=.        # profiles.yml is in the repo, DuckDB file is created locally
dbt build                        # 8 models, 30 tests (3 warn on purpose, see "Known data issues")
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

Staging cleans, renames and adds row-level flags (`is_timeout`, `has_no_sources`). The intermediate model combines them into the shared definitions (`is_technical_success`, rated, thumbs down), so the marts share the same flags. They use two thumbs-down rates on purpose: Q1 and Q2 use all rated answers (what users said); the North Star conditions on technically sound answers to avoid counting a failure twice. With technical failures around 1%, the two differ by less than one point.

Weeks are ISO weeks (Monday start) in UTC. Windows are anchored to the `as_of_date` var, which defaults to the last day in the data (19 April 2026); moving it back is how I tested the sensitivity of the answers.

Answer queries are in [`analyses/`](analyses/); exposures in [`models/marts/exposures.yml`](models/marts/exposures.yml).

## The short version

From the week of 23 March, AMA quality drops sharply in **one large enterprise account, ws_0041**: its thumbs-down rate goes from 24% to 77%, across all six modules, with 30 of its 53 active users rating answers down. Outside it, the platform moves only slightly. Q1 and Q2 therefore lead to the same finding from two angles, and the North Star (Q3) shows it as a step from about 0.75 to about 0.65. In parallel, AMA usage falls across the whole platform.

## Answers

### Q1: AMA quality trend per module

[`analyses/q1_ama_quality_by_module.sql`](analyses/q1_ama_quality_by_module.sql) gives the weekly trend; [`analyses/q1_module_focus.sql`](analyses/q1_module_focus.sql) compares the last 4 weeks (23 Mar to 19 Apr) with the 4 before; [`analyses/q1_regression_concentration.sql`](analyses/q1_regression_concentration.sql) checks where the change comes from.

| Module | Answers (last 4w) | Rated | Thumbs down | Thumbs-down rate: prev 4w → last 4w |
|---|---|---|---|---|
| **All modules** | 1,816 | 475 | 168 | 25.4% → 35.4% |
| civile | 789 | 203 | 69 | 23.7% → 34.0% |
| societario | 279 | 74 | 30 | 25.9% → 40.5% |
| lavoro | 319 | 74 | 26 | 27.7% → 35.1% |
| tributario | 191 | 50 | 19 | 26.8% → 38.0% |
| penale | 163 | 56 | 15 | 22.4% → 26.8% |
| amministrativo | 75 | 18 | 9 | 31.9% → 50.0% |

Every module looks worse, but that is not a module story. Split by account:

| Segment | Rated (prev → last 4w) | Thumbs-down rate |
|---|---|---|
| All workspaces | 1,437 → 475 | 25.4% → 35.4% |
| **ws_0041 only** | 166 → 56 | **23.5% → 76.8%** |
| All except ws_0041 | 1,271 → 419 | 25.6% → 29.8% |
| Enterprise except ws_0041 | 958 → 322 | 25.3% → 29.2% |
| Pro and free | 312 → 97 | 26.9% → 32.0% |

ws_0041 is the largest account (about 12% of answers) and produces 26% of all thumbs down since 23 March. Because it uses every module, it makes every module look worse at the same time. Without it the platform rises about 4 points, which is within noise at these volumes (z ≈ 1.6).

Where Product should focus:

1. **ws_0041 first**: what changed for this account around 23 March (content it asks about, a configuration, a document set, a language setting)? It is the one clear regression in the data and it is also the top CS risk (Q2).
2. **Then civile**, if one module must come first: it carries 41% of thumbs down in the last 4 weeks, so a fix there helps the most users.
3. The per-module differences (societario, tributario, amministrativo) are within noise once ws_0041 is set aside: worth watching, not yet a decision.

Timeouts and answers without sources stay around 1% throughout, so whatever happened is about answer content, not infrastructure.

Most module-weeks have fewer than 30 ratings (`is_low_sample`), so the weekly per-module trend is readable only as a direction; the 4-week comparison is the version to decide on.

### Q2: account health risk

`risk_score` (0 to 100) compares each workspace's last 28 days with the 28 days before, and computes every signal again one week earlier:

| Signal | Points | Fires when | Why it matters |
|---|---|---|---|
| Quality drop | 40 if also present one week earlier, 20 if only this week | Thumbs-down rate ≥ 10 points higher, with ≥ 15 ratings in both periods | Users are telling us directly the product got worse for them |
| Usage drop | 30 | Answers below half of what the platform trend predicts for this workspace (≥ 30 answers before) | Leading indicator of churn |
| Users drop | 20 | Active users below half of what the platform trend predicts (≥ 5 users before) | Adoption is shrinking inside the account |
| Failed answers | 10 | ≥ 3% of answers timed out or had no sources (≥ 20 answers) | A technical issue CS can escalate, rarely a churn reason alone |

`high` ≥ 40, `medium` 20 to 39, `low` below 20 when there are enough ratings to judge, **`not enough data`** below 20 without them. A confirmed quality drop alone makes an account high; usage, users, or an unconfirmed quality drop alone make it medium; failed answers alone never go above low.

Result:

| Workspace | Plan | Level | Why |
|---|---|---|---|
| **ws_0041** | enterprise | **high** | Thumbs down 23% → 77% (166 → 56 ratings), confirmed one week earlier |
| ws_0003 | pro | medium | Usage collapsed: 38 → 5 answers |
| ws_0029 | enterprise | medium | Thumbs down 24% → 36%, this week only |
| ws_0017 | enterprise | medium | Thumbs down 24% → 37%, this week only |
| ws_0076 | enterprise | medium | Thumbs down 23% → 33%, this week only |

Plus 6 low, and **69 not enough data**: with usage down, only 10 workspaces have at least 15 ratings in both periods. Two of those 69 are worth a manual look even without a score: ws_0051 (enterprise) and ws_0077 (pro) went to 73% and 67% thumbs down, on 11 and 9 ratings.

**Why the confirmation rule.** Without it the high list depended heavily on the window: anchored on 12 April it had six accounts, on 19 April four, and only ws_0041 was in both. A CS lead cannot act on a list that reshuffles every week. Requiring the drop in two consecutive windows keeps the one account that is clearly deteriorating at the top, and leaves the others as medium to watch.

**Why usage is relative to the platform.** Across the platform, answers in the last 28 days are 34% of the previous 28, while active users are 87%: people still log in but ask far fewer questions. My first version used absolute thresholds and small minimum volumes, and 36 of 80 workspaces came out high. An account is flagged only if it declines clearly more than everyone else. Quality uses an absolute threshold instead, because outside ws_0041 the platform's quality is nearly flat, so absolute and relative give the same answer here.

**Known limits.** On this data the score is effectively driven by the quality signal: users drop fires for no account, usage drop and failed answers for one each. The four signals are designed for production volumes. Thresholds and weights are explainable rather than fitted, and should be calibrated against real churn.

### Q3: AMA North Star

**Good answer rate** = P(technically sound) × P(not rated down | technically sound)

```
good_answer_rate = technical_success_rate × (1 − thumbs_down_rate_successful)
```

- `technical_success_rate`: share of answers with no timeout and at least one retrieved source (measured on 100% of answers).
- `thumbs_down_rate_successful`: thumbs down / rated answers, among technically sound answers (measured on the ~27% of answers that get rated).
- Grain: week. Window: last 8 weeks up to `as_of_date`.

| Week | Answers | Rated | Good answer rate |
|---|---|---|---|
| 23 Feb | 1,714 | 448 | 0.71 |
| 2 Mar | 1,492 | 394 | 0.77 |
| 9 Mar | 1,180 | 317 | 0.77 |
| 16 Mar | 989 | 278 | 0.73 |
| 23 Mar | 840 | 229 | 0.66 |
| 30 Mar | 552 | 142 | 0.63 |
| 6 Apr | 322 | 84 | 0.65 |
| 13 Apr | 102 | 20 | 0.50 (low sample) |

A step down from about 0.75 to about 0.65 from the week of 23 March, largely driven by ws_0041 (see Q1). Weekly values carry about ±0.04 of noise at 450 ratings, ±0.10 at 84 and ±0.22 at 20, so the last weeks should be read as a direction, not as values.

**Being honest about the formula.** Today the technical term is between 0.988 and 1.000 every week, so the North Star is essentially 1 − thumbs-down rate. I keep the technical term on purpose: it is the insurance that makes an infrastructure regression (timeouts, retrieval returning nothing) move the same number Leadership watches. If Leadership prefers, it can equally be shown as two numbers.

**Why the first version was dropped.** My first definition counted an answer as "good" when it had no technical failure and no thumbs down, over all answers. It stayed flat at 0.90 to 0.93 while the thumbs-down rate went from 25% to 35%, because the 73% of unrated answers counted as good and diluted the signal.

**The assumption, tested where possible.** The formula assumes that users who rate are representative of those who don't. On everything observable, rated and unrated answers look the same: median latency 2,946 vs 2,942 ms, median tokens 1,168 vs 1,172, median sources 5 vs 5, cached 14.9% vs 15.1%, no sources 0.7% vs 0.6%. The feedback rate is 26 to 29% every week except the last (20%, on 20 ratings), 25 to 31% per module, and differs little by role. What cannot be ruled out is selection on satisfaction itself (unhappy users rating more often); `feedback_rate` is in the mart to monitor it.

**Left out on purpose:** latency. Cached answers make it bimodal (~0.1 s vs ~3.2 s) and only 7% of thumbs down are tagged `slow`. It stays as a diagnostic column.

### Usage

AMA volume fell from ~1,900 answers a week in mid-February to ~320 in early April and ~100 in the last week, while active workspaces went from 67 to 33. Volume steps down every Monday and is flat within each week, which looks like how this synthetic data was generated. I first read the last step (13 April) as a truncated export and cut the data there; the same Monday step appears on 30 March and 6 April, so I dropped that cut-off rather than exclude the worst week. Whether real users are leaving after worse answers, or tracking changed, is the first question I would bring to Engineering.

## Known data issues and how they are handled

| Issue | Rows | Handling |
|---|---|---|
| Duplicate answers (same `event_id`) | 5 | One row per `event_id` (`QUALIFY ROW_NUMBER()`, latest wins), `unique` test. All 5 are exact copies today |
| Duplicate feedback | 15 | One rating per answer, latest wins; `unique` test on `event_id`. All 15 are exact copies today |
| `module_tag` in mixed case, plus `civil` for `civile` | 247 | Lowercased and mapped, `accepted_values` test |
| Negative latency | 33 | Set to null, flagged `has_invalid_latency`. Magnitudes match valid answers, so they look like sign flips; not guessed |
| Latency of exactly 900,000 ms | 28 | Kept and flagged `is_timeout`: 5 of the 6 rated were thumbs down |
| Uncached answers at exactly 300 ms, with short answers (median 125 tokens) | 71 | Kept as successes; looks like a fallback path worth asking Engineering about |
| Cached answers with odd values: 4 at the 900,000 ms timeout, 5 at exactly 45,000 ms, 12 with zero sources, 50 at exactly 20 ms | 71 | Kept as recorded. The 12 count as technical failures, which may be wrong if cache hits log zero retrieval |
| `thumbs` of -2, 0, 2 | 16 | Set to null, excluded from quality metrics |
| Thumbs down with free text but no `reason_tag` | 21 | Counted in `reason_missing`; the free text could be mapped to a reason |
| Feedback on answers missing from the export | 50 | Dropped when joined to answers; `relationships` test set to **warn**. They are 46% thumbs down vs 27% overall, so if the missing answers are failed generations, the thumbs-down rate is slightly understated |
| Answers from workspaces missing from `raw_workspaces` (ws_9000, ws_9001) | 8 | Kept for module metrics, excluded from the workspace mart; **warn** test |
| Users pointing to missing workspaces (u_orphan_0/1/2) | 3 | **warn** test |
| Workspaces without country | 3 | `unknown` |
| Answers earlier than the user's `created_at` | 817 (71 users) | Documented as unreliable, not filtered |
| Answers earlier than the workspace's `signup_date` | 597 (ws_0076: 511, ws_0019: 67, ws_0026: 19) | Flagged `is_before_workspace_signup`, not filtered; `signup_date` should not be used for tenure until fixed |

The three warnings are intentional: known upstream issues that should be visible on every run without blocking it.

Synthetic tells, noted rather than handled: answers are spread evenly across all 24 UTC hours (so the UTC vs CET choice changes almost nothing), feedback always arrives within 10 minutes, and volume steps down every Monday.

## Tests that matter

Beyond keys, accepted values and relationships, four singular tests:

- `assert_marts_reconcile_to_answers`: every answer is counted exactly once in both weekly marts. Protects every rate from fan-out in the feedback join or rows dropped by a filter.
- `assert_rates_and_counts_in_range`: rates between 0 and 1, and thumbs down ≤ rated ≤ answers. Catches broken denominators and filters applied to one side of a ratio only.
- `assert_reasons_reconcile_to_thumbs_down`: the reason columns (including `other` and `missing`) add up to the thumbs down, so a PM summing them gets the total.
- `assert_module_week_is_unique`: enforces the declared grain of the module mart.

Some tests guard against regressions rather than today's data: `unique` on the deduplicated keys and `not_null` on `risk_score` cannot fail with the current SQL, but would catch someone removing the `QUALIFY` or a `COALESCE`. The `not_null` on `risk_score` did catch a real bug during development (workspaces with no recent activity got a null score). `assert_feedback_after_answer` protects against the two event streams drifting out of sync; it cannot fire on this synthetic data but would in production.

## Trade-offs

- **Unrated answers.** The North Star assumes raters are representative; checked on observables, not on satisfaction itself.
- **Risk score thresholds and weights** are explainable rather than fitted. The confirmation rule trades speed for stability: a genuinely new drop shows as medium for a week before it becomes high.
- **28-day windows vs ISO weeks.** The workspace mart uses rolling 28 days to smooth small accounts; the weekly marts use calendar weeks for readability.
- **Views for staging and intermediate, tables for marts.** Fine at this size; in production the intermediate would become an incremental table partitioned by date.

## What I would do next

1. Ask Engineering and CS what changed for ws_0041 around 23 March, and whether the platform-wide usage decline is real.
2. Calibrate the risk score against real churn or downgrade events, and weight accounts by revenue or seats.
3. Add confidence intervals (or a Wilson lower bound) to the weekly rates, so low-sample weeks are visible in the number and not only in a flag.
4. Add source freshness and row-count anomaly checks on the Pub/Sub landing tables.
5. Track `feedback_rate` per module: if it moves, the North Star is no longer comparable over time.
6. The optional engineering DORA mart (`raw_engineering_prs.csv`): skipped to stay within the time budget. The simplest useful metric would be weekly median lead time from PR open to merge, per team.

## How I used AI

I used Claude Code throughout: to profile the raw data with ad hoc DuckDB queries, scaffold the project, and draft SQL, YAML and documentation. The modelling and metric decisions are mine: grain of each mart, the North Star definition and its revision, the risk signals, weights and thresholds, and which data issues to fix, flag or tolerate. I also had a second model review the project adversarially twice, recomputing the README numbers from the raw data. Those reviews changed the analysis in substance: the North Star conditioning, the risk score volume minimums and confirmation rule, dropping a date cut-off I had introduced, and, most importantly, seeing that the "platform-wide" regression was one account. I reviewed every model and checked the numbers in this README against the marts.
