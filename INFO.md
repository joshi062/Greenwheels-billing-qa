# Greenwheels Billing QA — File-by-File Overview

---

## 1. `README.md`
The project's landing page. Covers:
- **Repo structure** — maps every folder/file and its purpose.
- **Prerequisites** — Docker Compose, Node.js 18+/20+, Newman CLI.
- **Setup & execution** — 4-step workflow: `docker compose up -d` → `curl` health check → `newman run` → `docker compose down -v`.
- **Key assumptions** — 4 seeded driver fixtures (`drv_active_001`, `drv_paused_002`, `drv_terminated_003`, `drv_overdue_004`), synchronous projection in the stub (<100 ms), placeholder Bearer token, and 2 intentional stub defects.
- **Known gaps** — eventual-consistency polling, parallel concurrency testing limits in Newman, missing step definitions for Gherkin, and no direct event-store schema contract checks.

---

## 2. `TEST_PLAN.md`
The full test strategy document (~226 lines). Contains:
- **Executive summary** — the Billing Cycle microservice handles weekly invoices, discounts, payments, and ledger projections for a lease-to-own motorcycle fleet.
- **Scope** — 5 API endpoints (`POST /billing/cycles`, `POST /billing/payments`, `GET /billing/cycles/{driver_id}`, `POST /billing/discounts`, `GET /billing/summary/{driver_id}`). Out-of-scope: real payments, AWS infra, UI, load tests.
- **Assumptions** — 9 explicit assumptions including JSON bodies, Bearer auth, consecutive-miss definition, decimal currency precision, and bounded projection delay.
- **Risk matrix** — 5 risks rated P0–P2 (non-idempotent payments, currency drift, consecutive-miss miscount, discount stacking, paused/terminated lease billing).
- **Event-sourced testing strategy (§5)** — Command-Fact-Projection triad verification, idempotency/replay invariance, order-dependent state derivation, no direct DB mutation.
- **Entry/exit criteria** — green suite is necessary but not sufficient; also requires zero unresolved Critical/High defects, proven idempotency, reconciled projections, and release-owner sign-off.
- **Test data strategy** — deterministic fixture records for each driver archetype.
- **Scale design notes (§11)** — covers 500K invoices in a 4-hour window, k6 load profiles (baseline, ramp, sustained, burst, stress, soak, recovery, country-mix), 0.1% concurrent duplicate injection, and 5-country regression parameterization.

---

## 3. `DEFECTS.md`
Two root-cause defect reports for the intentional stub bugs:

- **DEF-BILL-001 (Critical / P0)** — `POST /billing/payments` is not idempotent by `payment_reference`. Re-submitting the same reference appends a second `PaymentFactRecorded` event, doubling `total_paid` and creating a negative `total_outstanding`. Root cause: no `UNIQUE` constraint on `payment_reference` and no duplicate check in the command handler.
- **DEF-BILL-002 (High / P1)** — `POST /billing/discounts` and `POST /billing/cycles` fail to enforce domain guards. Discounts stack (two 400 KES discounts reduce `amount_due` by 800 instead of 400) and/or carry over into the next week. Alternatively, billing cycles are generated for paused leases. Root cause: the projector uses a cumulative `SUM()` on discount facts without filtering by target week or marking them consumed.

---

## 4. `AI_USAGE.md`
Transparent AI disclosure document with 4 sections:
- **§1 — Tools used** — Gemini/Claude for scaffolding, GitHub Copilot for inline completions.
- **§2 — Where AI accelerated work** — Postman JSON boilerplate (~70% time saved), Gherkin Scenario Outline formatting (~80%), and the `jq`-based GitHub Actions summary reporter.
- **§3 — Where AI was rejected/corrected** — 4 rejections: (1) shallow 200-status checks vs. CQRS read-after-write chains, (2) total vs. consecutive missed payment counts, (3) serial vs. concurrent idempotency testing at scale, (4) Newman timeout-only vs. pre-flight `curl` SLA gate.
- **§4 — Manually added test cases** — discount carry-over verification, INR/NPR currency trap, accounting equation invariant, and boundary guards (week 0, negative amounts).

---

## 5. `.github/workflows/qa.yml`
GitHub Actions CI pipeline (85 lines) triggered on PRs to `main`/`master`/`develop` and pushes to `main`. Single job `api-quality-gate` with 7 steps:
1. **Checkout** — `actions/checkout@v4`.
2. **Start stub** — `docker compose up -d`.
3. **5-second SLA gate** — `curl --max-time 5` against `/billing/summary/drv_active_001`; fails the pipeline with container logs if the stub doesn't respond in time.
4. **Setup Node.js 20** — `actions/setup-node@v4`.
5. **Install Newman** — `npm install -g newman newman-reporter-junitfull`.
6. **Execute Newman** — runs the collection with `--timeout-request 5000`, exports JSON + JUnit XML results.
7. **PR summary** — parses `newman-results.json` with `jq` to extract total/passed/failed assertions, request count, and average response time; writes a Markdown table to `$GITHUB_STEP_SUMMARY`; lists individual failures if any.
8. **Teardown** — `docker compose down -v` (always runs).

---

## 6. `postman/collection.json`
Postman v2.1 collection (588 lines) with Bearer token auth and 3 folders:

### Folder 1 — Happy Path Scenarios (5 requests)
| ID | Endpoint | What it validates |
|:--|:--|:--|
| HP-01 | `POST /billing/discounts` | 200/201, response has `driver_id`, `currency: KES`, `discount_amount: 500` |
| HP-02 | `POST /billing/cycles` | 201/200, response has `invoice_id`, `amount_due`, `currency: KES`, `due_date`; stores `active_invoice_id` and `active_amount_due` in env |
| HP-03 | `POST /billing/payments` | 200/201, response has `payment_reference`, `invoice_id`, `amount`, `currency: KES`, status is `recorded`/`paid`/`success` |
| HP-04 | `GET /billing/cycles/{driver_id}` | 200, returns array of cycles with valid `status` enum (`pending`/`paid`/`overdue`/`disputed`) |
| HP-05 | `GET /billing/summary/{driver_id}` | 200, `total_outstanding == total_billed - total_paid` (accounting equation invariant) |

### Folder 2 — Business Rule Validation (5 requests)
| ID | Rule | What it validates |
|:--|:--|:--|
| BR-01 | Paused lease guard | `POST /billing/cycles` for `drv_paused_002` → 400/409/422 with lease-state error message |
| BR-02 | Payment idempotency | Re-submits same `payment_reference`, then chains `pm.sendRequest()` to GET summary and asserts `total_paid` is unchanged |
| BR-03 | 3 consecutive missed → overdue | GET summary for `drv_overdue_004`, asserts `missed_payment_count >= 3` and overdue status |
| BR-04 | No discount stacking/carry-over | Pre-request applies a discount; main request applies a second; then chains a POST for week 13 and asserts `amount_due` reverts to `base_weekly_rate` |
| BR-05 | Strict KES currency | `POST /billing/payments` with `USD` → 400/422 with error mentioning KES |

### Folder 3 — Negative & Edge Cases (5 requests)
| ID | Scenario | Expected |
|:--|:--|:--|
| NEG-01 | Terminated lease cycle | 400/409/422, error mentions "terminated" |
| NEG-02 | Missing `payment_reference` | 400/422, error identifies missing field |
| NEG-03 | Discount with `INR` currency | 400/422 |
| NEG-04 | `week_number: 0` boundary | 400/422 |
| NEG-05 | Negative payment amount (`-1500`) | 400/422 |

---

## 7. `postman/env.json`
Postman environment file (49 lines) with 7 variables:

| Variable | Value | Purpose |
|:--|:--|:--|
| `base_url` | `http://localhost:8000` | Stub service base URL |
| `driver_id` | `drv_active_001` | Default active driver fixture |
| `paused_driver_id` | `drv_paused_002` | Paused lease fixture |
| `terminated_driver_id` | `drv_terminated_003` | Terminated lease fixture |
| `overdue_driver_id` | `drv_overdue_004` | 3-consecutive-miss fixture |
| `base_weekly_rate` | `4000` | Base lease rate in KES |
| `auth_token` | `PLACEHOLDER_BEARER_TOKEN...` | Non-sensitive CI placeholder |

---

## 8. `features/consecutive_missed_payments_and_discounts.feature`
Gherkin BDD spec (36 lines) covering two business rules:

**Scenario Outline 1 — Consecutive missed payment overdue projection**
- Background: driver `drv_active_001` with active lease at 4000 KES/week.
- Uses a `payment_history` column with explicit event sequences (e.g., `PAID, MISSED, MISSED, MISSED`).
- 4 example rows testing 2, 3, 1, and 4 consecutive misses.
- Key row: `drv_hist_003` with `MISSED, MISSED, PAID, MISSED` → only 1 consecutive miss → `active` (not overdue). This disproves a naive total-count implementation.

**Scenario Outline 2 — Single-week discount without stacking or carry-over**
- Applies a first discount, then a second, generates cycles for weeks 21 and 22.
- 3 example rows verifying: single discount applies, second discount is ignored (no stacking), and week 22 reverts to full base rate (no carry-over).

---

## 9. `features/lease_state_billing_guard.feature`
Gherkin BDD spec (34 lines) covering two domain guard rules:

**Scenario Outline 1 — Lease state eligibility**
- 3 example rows: `active` → 201 + invoice generated (1 fact emitted), `paused` → 409 + rejected (0 facts), `terminated` → 409 + rejected (0 facts).
- Asserts the number of `BillingCycleGenerated` facts recorded — event-store-level verification.

**Scenario Outline 2 — Strict KES currency validation**
- 4 example rows: `KES` → 201 accepted, `INR` → 400 rejected, `NPR` → 400 rejected, `USD` → 400 rejected.
- Tests the currency guard on `POST /billing/cycles` specifically.

