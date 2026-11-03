# AI Usage Disclosure (`AI_USAGE.md`)

## 1. AI Tools Used
* **Gemini / Claude (Large Language Models):** Used for test plan scaffolding, generating Postman v2.1 JSON boilerplate, drafting initial Gherkin `Scenario Outline` tables, and structuring the GitHub Actions `jq` summary parser.
* **GitHub Copilot (IDE Assistant in VS Code):** Used for inline autocompletion of Postman `pm.test` Chai assertions, YAML syntax validation in `.github/workflows/qa.yml`, and Markdown table formatting.

---

## 2. Where AI Meaningfully Accelerated Work
* **Postman v2.1 Collection JSON Scaffolding (~70% time saved on boilerplate):** Hand-writing raw Postman v2.1 JSON schemas is error-prone. I used AI to generate the structural skeleton and environment variable bindings, allowing me to focus on assertion logic and request chaining.
* **Gherkin `Scenario Outline` & Examples Formatting (~80% of initial structure):** Once I defined the exact business rules to cover, AI rapidly generated the Cucumber `Background`, `Scenario Outline`, and `Examples` tables.
* **GitHub Actions PR Summary Reporting (`qa.yml`):** AI accelerated writing the bash + `jq` parsing block that extracts `.run.stats.assertions` and `.run.failures[]` from `newman-results.json` and formats them into a Markdown table for `$GITHUB_STEP_SUMMARY`.

---
# Section 3 Analysis: Where AI Output Was Rejected or Corrected

Cross-referencing each of the 4 rejections in [AI_USAGE.md](file:///c:/Users/Lenovo/Downloads/Greenwheels-billing-qa/AI_USAGE.md#L16-L36) against every file in the repo to show **where the correction landed and what the evidence looks like**.

---

## Rejection 1: Stateful CRUD Testing Assumptions vs. Event-Sourced CQRS Reality

> AI only asserted `pm.response.to.have.status(200)` on write endpoints. You corrected it to chain `pm.sendRequest()` read-after-write assertions.

### Evidence across files

| File | What we see | Lines |
|:--|:--|:--|
| [collection.json](file:///c:/Users/Lenovo/Downloads/Greenwheels-billing-qa/postman/collection.json#L246-L261) | **BR-02** chains a `pm.sendRequest()` GET to `/billing/summary/{driver_id}` inside the test script of the duplicate-payment POST, verifying `total_paid` and `total_outstanding` in the projection — not just the write status. | L251–L261 |
| [collection.json](file:///c:/Users/Lenovo/Downloads/Greenwheels-billing-qa/postman/collection.json#L340-L359) | **BR-04** uses a `pm.sendRequest()` in both pre-request and test scripts to POST a discount, then POST a cycle for week 13, and assert `amount_due` reverts to the base rate in the **read model**. | L320–L358 |
| [TEST_PLAN.md](file:///c:/Users/Lenovo/Downloads/Greenwheels-billing-qa/TEST_PLAN.md#L79-L84) | Section 5 ("Testing Strategy for an Event-Sourced Architecture") explicitly codifies the **Command-Fact-Projection Triad** rule: *"A `200/201` response on a `POST` endpoint only proves the command was accepted. Every write test is immediately paired with a read assertion."* | L81 |
| [DEFECTS.md](file:///c:/Users/Lenovo/Downloads/Greenwheels-billing-qa/DEFECTS.md#L14-L15) | **DEF-BILL-001** reproduce steps show the chained read: step 5 queries `GET /billing/summary/drv_active_001` to prove double-credit — confirming the read-after-write pattern was applied. | L14–15 |
| [README.md](file:///c:/Users/Lenovo/Downloads/Greenwheels-billing-qa/README.md#L88-L89) | Assumption #2 explicitly notes the stub projects events synchronously or within <100 ms, which is why the chained `pm.sendRequest()` works without a polling loop. | L88–89 |

> **Takeaway:** The AI's shallow "just check 200" was replaced everywhere with projection-verification chains. This is the single most impactful correction — it's the foundation that made DEF-BILL-001 discoverable.

---

## Rejection 2: Total Missed Payments vs. *Consecutive* Missed Payments in Gherkin

> AI generated Examples varying total counts (`1`, `2`, `3`) without testing sequence order. You replaced them with explicit `payment_history` event sequences.

### Evidence across files

| File | What we see | Lines |
|:--|:--|:--|
| [consecutive_missed_payments_and_discounts.feature](file:///c:/Users/Lenovo/Downloads/Greenwheels-billing-qa/features/consecutive_missed_payments_and_discounts.feature#L10-L22) | The `Scenario Outline` uses a `payment_history` column with explicit event sequences like `MISSED, MISSED, PAID, MISSED`. Row `drv_hist_003` is the critical counter-example: 3 total misses but only **1 consecutive** → `active`, not `overdue`. | L10–22 |
| [TEST_PLAN.md](file:///c:/Users/Lenovo/Downloads/Greenwheels-billing-qa/TEST_PLAN.md#L53) | Risk row "Projection Lag & Consecutive Missed-Payment Miscount" (P1) explicitly warns: *"Counting total missed payments instead of consecutive missed payments will falsely flag compliant drivers."* Mitigation: "Sequence-based state projection tests." | L53 |
| [TEST_PLAN.md](file:///c:/Users/Lenovo/Downloads/Greenwheels-billing-qa/TEST_PLAN.md#L41) | Assumption 7: *"The system's definition of 'three consecutive missed payments' is based on consecutive billing periods, not a lifetime total."* | L41 |
| [collection.json](file:///c:/Users/Lenovo/Downloads/Greenwheels-billing-qa/postman/collection.json#L282-L311) | **BR-03** reads `overdue_driver_id` (fixture `drv_overdue_004`) and asserts `missed_payment_count >= 3` and overdue status. The fixture itself embodies a consecutive-miss history. | L282–311 |
| [env.json](file:///c:/Users/Lenovo/Downloads/Greenwheels-billing-qa/postman/env.json#L30-L34) | The `overdue_driver_id` variable (`drv_overdue_004`) is a purpose-built fixture for the consecutive-miss scenario. | L30–34 |

> **Takeaway:** The key corrective evidence is `drv_hist_003` (`MISSED, MISSED, PAID, MISSED` → consecutive count = 1, status = `active`). A naive `COUNT(*)` would return 3 and wrongly flag overdue. This row is the proof that AI's total-count approach was insufficient.

---

## Rejection 3: Serial Idempotency Testing in Scale Exercise

> AI suggested replaying 500 duplicates at the end of a load test. You redesigned it to split into concurrent race duplicates and delayed retry duplicates.

### Evidence across files

| File | What we see | Lines |
|:--|:--|:--|
| [TEST_PLAN.md](file:///c:/Users/Lenovo/Downloads/Greenwheels-billing-qa/TEST_PLAN.md#L178-L200) | **Section 11.3** ("Idempotency at scale with 0.1% duplicate payment submissions") is the corrected design. It specifies: concurrent submissions for the same reference, retries after simulated client timeouts, duplicates across worker instances and service restarts — not just serial replay. | L178–200 |
| [TEST_PLAN.md](file:///c:/Users/Lenovo/Downloads/Greenwheels-billing-qa/TEST_PLAN.md#L185-L186) | Point 2: *"Distribute duplicates across the full run, including **bursts and concurrent submissions** for the same reference, plus retries after simulated client timeouts where the server may already have committed."* | L185–186 |
| [TEST_PLAN.md](file:///c:/Users/Lenovo/Downloads/Greenwheels-billing-qa/TEST_PLAN.md#L139) | Failure point #2 in Section 11.1 explicitly calls out: *"workers may retry after a timeout even when the transaction committed, creating duplicate invoices."* | L139 |
| [DEFECTS.md](file:///c:/Users/Lenovo/Downloads/Greenwheels-billing-qa/DEFECTS.md#L1-L24) | **DEF-BILL-001** proves why serial-only testing is dangerous: even a single sequential replay creates a double-credit. Under concurrent load, the risk compounds. | L1–24 |

> **Takeaway:** The AI's serial-replay approach would have tested **cache lookups under zero contention** only. The corrected design in Section 11.3 specifically mandates sub-millisecond concurrent race conditions, cross-worker duplicates, and post-timeout retries — the scenarios that actually expose idempotency failures in distributed systems.

---

## Rejection 4: Incomplete 5-Second SLA Enforcement in CI

> AI added `--timeout-request 5000` to Newman and assumed that covered the SLA. You added a pre-flight `curl --max-time 5` gate step.

### Evidence across files

| File | What we see | Lines |
|:--|:--|:--|
| [qa.yml](file:///c:/Users/Lenovo/Downloads/Greenwheels-billing-qa/.github/workflows/qa.yml#L24-L35) | The **"Enforce 5-Second Service Readiness & Response SLA Gate"** step runs `curl --max-time 5` before Newman even starts. If the stub fails to respond within 5 seconds, the entire pipeline exits with a clear error and dumps `docker compose logs`. | L24–35 |
| [qa.yml](file:///c:/Users/Lenovo/Downloads/Greenwheels-billing-qa/.github/workflows/qa.yml#L48-L53) | Newman still runs with `--timeout-request 5000`, but this is now the **second layer** of SLA enforcement, not the only one. | L48–53 |
| [qa.yml](file:///c:/Users/Lenovo/Downloads/Greenwheels-billing-qa/.github/workflows/qa.yml#L26-L31) | The gate measures elapsed time with millisecond precision (`date +%s%3N`) and validates both the HTTP status code (`!= 000`) and the elapsed time (`<= 5000ms`). | L26–31 |
| [README.md](file:///c:/Users/Lenovo/Downloads/Greenwheels-billing-qa/README.md#L47-L49) | The manual setup instructions also include the `curl --max-time 5` verification step, reinforcing that this is a deliberate SLA check, not just a CI artifact. | L47–49 |

> **Takeaway:** `--timeout-request 5000` only gates individual HTTP requests *during* the test run. It does **not** verify whether the stub container itself is healthy and responsive before tests begin. The `curl` pre-flight gate closes this gap — if the container hangs on startup or crashes, Newman never runs and the pipeline fails fast with diagnostic logs.

---

## Summary: What Can We Write in Section 3

The 4 rejections already in [AI_USAGE.md](file:///c:/Users/Lenovo/Downloads/Greenwheels-billing-qa/AI_USAGE.md) are **well-supported and traceable** across the codebase. Here's a confidence assessment:

| Rejection | Files with supporting evidence | Strength |
|:--|:--|:--|
| **1. CRUD → CQRS read-after-write** | collection.json (BR-02, BR-04), TEST_PLAN.md §5, DEFECTS.md, README.md | ✅ **Strong** — correction is visible in test code and documented in strategy |
| **2. Total → Consecutive missed payments** | feature file (drv_hist_003 row), TEST_PLAN.md §5 risk matrix + assumption 7, collection.json BR-03, env.json | ✅ **Strong** — the counter-example row (`PAID,MISSED,PAID,MISSED`) is the proof |
| **3. Serial → Concurrent idempotency** | TEST_PLAN.md §11.3, §11.1 failure point 2, DEFECTS.md DEF-BILL-001 | ✅ **Strong** — design section explicitly mandates concurrent + cross-worker testing |
| **4. Newman-only → Pre-flight SLA gate** | qa.yml (curl step), README.md (manual verification), qa.yml (Newman timeout) | ✅ **Strong** — two-layer SLA enforcement is directly visible in the pipeline |

> [!TIP]
> The section as currently written is already solid. If you want to strengthen it further, you could add **file-path cross-references** (e.g., "see `BR-02` in `postman/collection.json`") to each rejection so a reviewer can click through to the evidence.

---

## 4. Test Cases & Assertions Missed by AI That Were Added Manually
1. **Discount Carry-Over Verification Across `week + 2` (`BR-04`).**
2. **Domain Context Currency Trap (`INR` / `NPR` vs. `KES`).**
3. **Accounting Equation Invariant Assertion (`total_outstanding == total_billed - total_paid`).**
4. **Boundary Week & Negative Monetary Amount Guards (`week 0`, `amount: -1500`).**
