
# Greenwheels Bike — Billing Cycle Service Quality & Test Plan

## 1. Executive Summary & Objective
The Billing Cycle microservice governs weekly invoice generation, discount application, payment fact recording, and financial account projections for Greenwheels Bike's lease-to-own fleet operations. Because a driver's path to motorcycle ownership depends directly on accurate billing and ledger projections, this test strategy prioritizes **event-stream determinism, idempotency, state-machine enforcement, and strict currency validation**.

---
## 2. Purpose

Validate the Billing Cycle API for financial correctness, business-rule compliance, idempotency, auditability, and reliable behavior in an event-sourced microservices environment. The plan covers the five specified API endpoints and release sign-off criteria.

## 3. Scope & Out-of-Scope

### In scope
- `POST /billing/cycles`: create a weekly billing cycle and validate `invoice_id`, `amount_due`, `currency`, and `due_date`.
- `POST /billing/payments`: record payment facts and verify idempotency by `payment_reference`.
- `GET /billing/cycles/{driver_id}`: retrieve cycles and validate statuses (`pending`, `paid`, `overdue`, `disputed`).
- `POST /billing/discounts`: apply an eligible discount to the next week's cycle only; validate non-stacking and non-carry-over behavior.
- `GET /billing/summary/{driver_id}`: validate totals and missed-payment count, including the three-consecutive-missed-payments rule.
- Positive, negative, boundary, regression, API-contract, integration, and event/projection consistency tests.
- Currency validation (`KES`) on every write endpoint.
- Authentication behavior where defined by the stub service.
- CI execution using Newman and GitHub Actions.

### Out of scope
- Real payment-provider settlement or bank reconciliation.
- Production AWS infrastructure, disaster recovery, and multi-region failover.
- UI/browser testing.
- Load, soak, penetration, and formal compliance certification unless separately requested.
- Business rules not stated in the supplied requirements (for example, tax, proration, refunds, grace periods, discount caps, or exact due-date calculation).
- Definitive defect findings until the supplied stub service is available and the tests have been executed against it.

---
## 4. Assumptions and questions to confirm
1. Write requests accept a JSON body and return JSON.
2. Authentication uses `Authorization: Bearer <token>`.
3. The billing-cycle request uses `driver_id`, `week_number`, and `currency`.
4. The payment request uses `invoice_id`, `amount`, `currency`, and `payment_reference`.
5. The discount request uses `driver_id`, discount fields, and `currency`; the exact discount schema must be aligned with the stub's contract.
6. The stub provides deterministic test fixtures for active, paused, terminated, eligible, and ineligible drivers, or provides a documented fixture/reset mechanism.
7. The system's definition of “three consecutive missed payments” is based on consecutive billing periods, not a lifetime total.
8. Amounts are represented as decimal numbers or decimal strings. Tests should avoid binary floating-point equality where currency precision matters.
9. Eventual consistency has an agreed maximum projection delay. Where no delay is documented, tests must poll with a bounded timeout rather than assume immediate consistency.

These assumptions are explicit because endpoint schemas and fixture identifiers were not included in the assignment text. Update request bodies and fixture IDs to match the supplied stub contract before submission.

## 5. Risk Assessment Matrix

| Risk Area | Likelihood | Impact | Risk Level | Technical Justification & Mitigation |
| :--- | :---: | :---: | :---: | :--- |
| **Non-Idempotent Payment Recording** | High | Critical | **P0 (Blocker)** | Network retries or duplicate webhook deliveries with the same `payment_reference` could double-credit lease equity, causing direct revenue loss. *Mitigation: Automated duplicate-submission tests asserting invariant `total_paid` and `total_outstanding` balances.* |
| **Requirement-to-Implementation Currency Drift** | Medium | High | **P1 (High)** | While Greenwheels operates in  Kenya, Ghana, and Uganda , the core billing ledger specification strictly enforces `KES`. Accepting unvalidated currencies corrupts aggregate ledger projections. *Mitigation: Strict negative boundary tests on all `POST` endpoints.* |
| **Projection Lag & Consecutive Missed-Payment Miscount** | Medium | High | **P1 (High)** | Counting *total* missed payments instead of *consecutive* missed payments will falsely flag compliant drivers as `overdue`. *Mitigation: Sequence-based state projection tests.* |
| **Discount Stacking or Carry-Over Leakage** | Medium | Medium | **P2 (Medium)** | Submitting multiple discounts in the same week or carrying unused discounts across weeks erodes weekly lease margins. *Mitigation: Multi-discount sequence assertions on `amount_due` for `week + 1` and `week + 2`.* |
| **Billing Paused/Terminated Leases** | Low | High | **P1 (High)** | Charging a driver whose motorcycle is impounded, under repair (`paused`), or repossessed (`terminated`) creates legal and financial reconciliation disputes. *Mitigation: State-guard negative tests.* |

---

## 6. Test types and approach

### Functional
Validate each endpoint's normal behavior, response fields, status transitions, amount calculations, and summary aggregation.

### Negative
Test missing required fields, invalid types, unknown driver/invoice, unsupported currency, invalid discount, invalid week number, invalid amount, unauthorized access, and prohibited lease states.

### Boundary
Test zero and smallest permitted amount, amount precision, week-number boundaries, discount lower/upper limits, exactly two versus three consecutive missed payments, and billing around week/date boundaries. Confirm allowed limits with Product before asserting them.

### Integration
Verify the flow from cycle creation to payment recording and then to cycle-list/summary reads. Validate persistence and event propagation across services and PostgreSQL/event infrastructure where the stub exposes it.

### Regression
Every confirmed defect gets a deterministic regression test. Run the complete Newman suite on every pull request.
---

## 5. Testing Strategy for an Event-Sourced Architecture

In an event-sourced system, state is not mutated via `UPDATE` statements in PostgreSQL; instead, commands are validated against current state, immutable facts are appended to the event log, and read-model projections are derived from those facts. Our testing strategy addresses this paradigm specifically:

* **Command-Fact-Projection Triad Verification:** A `200/201` response on a `POST` endpoint only proves the command was accepted. Every write test in our suite is immediately paired with a read assertion against `GET /billing/cycles/{driver_id}` and `GET /billing/summary/{driver_id}`.
* **Idempotency & Replay Invariance:** Re-submitting an identical fact must either be rejected or treated as a no-op so that balances remain strictly invariant.
* **Order-Dependent State Derivation:** Tests are constructed as deterministic event streams to validate that the projector folds sequences accurately into `overdue` status.
* **No Direct Database Mutation in Tests:** Test data setup relies exclusively on seeding/issuing valid domain events via the API.

---

## 6. Entry criteria
- Requirements and API schemas reviewed.
- Stub service starts with the provided `docker-compose up` workflow.
- Test fixtures and reset strategy are documented.
- Test environment is reachable and test credentials are available.
- Collection variables are configured.
- Known limitations and unimplemented endpoints are recorded.

## 7. Exit criteria / release sign-off
- All critical business-rule tests pass.
- No unresolved Critical/High defects affecting billing amounts, duplicate credits, currency validation, lease eligibility, or overdue calculation.
- All write endpoints reject unsupported/missing currency as specified.
- Payment idempotency is proven by repeating the same `payment_reference` and reconciling totals.
- Cycle, payment, and summary views reconcile after the agreed projection window.
- Negative and boundary tests have executed with results recorded.
- Regression suite passes in CI; any exception is documented and explicitly accepted by the release owner.
- Logs/diagnostics are sufficient to investigate failed billing transactions.
- QA recommendation, residual risks, and release approval are recorded.

A green test suite is necessary but not sufficient: release approval also considers unresolved risk, monitoring, rollback readiness, and business acceptance.

---

## 8. Test data strategy
Use deterministic, isolated fixture records supplied by the stub or a reset/seed mechanism. Suggested logical fixtures:
- `active_driver`: eligible for billing.
- `paused_driver`: billing cycle must be rejected.
- `terminated_driver`: billing cycle must be rejected.
- `discount_eligible_driver` and `discount_ineligible_driver`.
- Drivers with 0, 1, 2, and 3 consecutive missed payments.
- `valid_invoice`: invoice available for payment.
- `unknown_driver_id` and `unknown_invoice_id`.


## 9. Defect management and reporting
Each defect should include an ID, concise title, environment/build, fixture and correlation IDs, steps, expected/actual behavior, evidence, severity, priority, suspected cause, and regression-test reference. Severity measures impact; priority measures urgency. Do not report an intentional defect as confirmed until reproduced against the supplied stub.

## 10. Metrics
Track critical business-rule pass rate, escaped billing defects, duplicate-payment prevention, invoice/summary reconciliation, automation stability, execution duration, defect reopen rate, and time to detect/recover from event-processing failures. Use code coverage as a diagnostic, not as a substitute for business-risk coverage.

## 11. Scale Considerations (Design Note — Do Not Implement)

This section describes the performance and scale-testing approach for the future target of five countries and 500,000 active drivers. It is a design note, not a requirement to implement load tests as part of this assignment. The production topology, service-level objectives (SLOs), country rule details, and infrastructure limits must be confirmed with Engineering before performance thresholds are finalized.

### 11.1 Scale model and likely first failure points

The weekly job must generate approximately 500,000 invoices inside a four-hour Sunday-night window. This equates to an average of about 125,000 invoices/hour, 2,083/minute, or 34.7/second. These averages are only a baseline: the system must be tested for bursts, retries, uneven country distribution, and downstream bottlenecks rather than sized from the average rate alone.

I would test the full billing path, not only the HTTP handler: request intake or scheduler, eligibility/rate/discount reads, invoice persistence, event publication, event consumers, projections, and summary/read APIs. Likely failure points, in the order I would investigate them, are:

1. **Database contention and connection-pool exhaustion:** concurrent invoice inserts, uniqueness checks, index hot spots, long transactions, lock waits, and exhausted PostgreSQL connections can cause rising latency and timeouts.
2. **Duplicate work and unsafe retries:** workers may retry after a timeout even when the transaction committed, creating duplicate invoices or financial effects unless operations are idempotent and uniqueness is enforced.
3. **Event-broker or consumer lag:** event publication/consumption throughput may fall behind invoice creation; projections and driver summaries then become stale.
4. **Dependency saturation:** discount/lease lookups, configuration services, or country-specific rule services may become the bottleneck or fail under burst traffic.
5. **CPU, memory, and worker saturation:** Python worker concurrency, serialization, garbage collection, and excessive per-request object allocation may reduce throughput.
6. **Hot partitions or uneven country/driver distribution:** a small number of partitions, indexes, or high-volume drivers may receive disproportionate traffic.
7. **Operational visibility gaps:** errors may be retried indefinitely or silently sent to a dead-letter queue without an actionable alert.

Detection should combine client-side load-test metrics with server-side telemetry. Capture throughput (completed invoices/second), p50/p95/p99 latency, error and timeout rate, queue depth and oldest-event age, event-consumer lag, database connection utilization, lock waits/deadlocks, query latency, CPU/memory, retry count, dead-letter count, duplicate invoice/payment counts, and reconciliation differences. Correlate requests/events using invoice IDs, driver IDs, payment references, and trace/correlation IDs. A run is not successful merely because requests return 2xx: all generated invoices and resulting financial facts must reconcile, with no unexplained duplicates, omissions, or incorrect totals.

### 11.2 Performance-test structure for the billing-cycle endpoint

**Tool choice:** Use **k6** for repeatable HTTP load profiles, thresholds, and CI-friendly output. If the team already standardizes on Locust, it is also suitable, particularly for modeling driver/country behavior in Python. Use one primary tool to avoid maintaining duplicate load frameworks. Pair the load generator with AWS/Prometheus/CloudWatch and PostgreSQL/event-broker telemetry.

**Test layers and load shape:**

- **Baseline/smoke:** a small number of virtual users against a clean test environment to verify the script, fixture setup, correctness checks, and telemetry.
- **Ramp test:** gradually increase request rate to the target average and beyond, recording the point where latency, errors, or queue lag start to degrade.
- **Sustained capacity test:** model the four-hour billing window at the required aggregate throughput. The average workload is approximately 34.7 invoices/second, but the agreed target must include expected retries, overhead, and headroom.
- **Burst test:** simulate a scheduler or worker fleet releasing work in bursts rather than perfectly evenly; observe database locks, queue depth, and recovery.
- **Stress test:** increase load beyond the expected peak until a bottleneck is found; verify graceful degradation and that failures do not create partial or duplicate financial effects.
- **Soak test:** sustain a representative load long enough to reveal connection leaks, memory growth, queue accumulation, and performance drift.
- **Recovery test:** interrupt/restart a worker or dependent component during load; verify backlog drains and reconciliation returns to zero without duplicate invoices.
- **Country mix:** use representative traffic and rule distributions for all five countries, including the busiest country and an uneven distribution. Do not assume identical currency, tax, calendar, or lease rules across countries.

The test data must be large enough to avoid unrealistic cache-only results and must be reset or uniquely namespaced between runs. Load generators must be provisioned so they do not become the bottleneck. Do not run destructive stress tests against production.

**Success criteria:** agree exact SLOs with Engineering/Product before execution. At minimum, require:
- Completion of the 500,000-invoice workload inside the four-hour window, with an agreed operational safety margin.
- No unexplained missing or duplicate invoices, payment facts, or billing events.
- No incorrect amount, discount, currency, lease eligibility, or invoice-period result.
- All writes satisfy idempotency and uniqueness constraints under concurrency and retries.
- p95/p99 endpoint latency and error rate remain within agreed SLOs at target load.
- Event queue lag and projection freshness remain within the agreed bound and return to normal after bursts.
- Database, worker, and broker utilization retain agreed headroom; no sustained connection exhaustion, deadlocks, or uncontrolled retries.
- A restart/failure during processing can recover without data loss or duplicate financial effects.
- Final reconciliation across requested cycles, persisted invoices, event facts, and projections has zero unexplained differences.

Performance thresholds such as p95 latency, error percentage, queue lag, and headroom must be explicit numeric values in the final test execution plan. They are intentionally not invented here because no product SLO or deployment capacity has been supplied.

### 11.3 Idempotency at scale with 0.1% duplicate payment submissions

At a 0.1% duplicate rate, the test workload should deliberately include duplicate submissions rather than relying on random collisions. For example, if the run submits 500,000 payment requests, 0.1% represents 500 duplicate submissions. Define whether the percentage means 0.1% additional replays or 0.1% of total requests are duplicates; record the chosen denominator in the test report.

Design the workload as follows:

1. Generate a deterministic set of valid invoices and unique payment references, with a controlled subset replayed using the **same** `payment_reference` and identical business payload. Add separate tests for a reused reference with a conflicting invoice or amount; the expected behavior must be explicitly defined and should never silently create a second credit.
2. Distribute duplicates across the full run, including bursts and concurrent submissions for the same reference, plus retries after simulated client timeouts where the server may already have committed.
3. Include duplicates across worker instances and, where supported, across service restarts. Keep a record of every intended logical payment and every HTTP submission.
4. Measure total submissions, unique payment references, duplicate attempts, accepted/replayed responses, payment facts created, credits applied, and invoice/summary balance changes.
5. Reconcile each unique logical payment to exactly one financial effect. A duplicate request may return a success or an idempotent/conflict response according to the API contract, but it must not create another credit.
6. Validate that a reused reference with a different payload is handled according to a defined conflict policy, is observable, and cannot corrupt the original payment record.

**Key metrics and assertions:**
- `duplicate_attempts / total_submissions` matches the configured duplicate ratio within the test generator's exact count.
- Number of distinct recorded logical payment references equals the expected unique-payment count.
- Each logical payment reference has at most one applied financial effect.
- The duplicate-credit count is exactly zero.
- No invoice's paid amount exceeds the expected total except where explicit overpayment behavior permits it.
- Reconciliation differences between payment facts, invoice totals, and summaries are zero after the projection-consistency window.
- Duplicate/idempotency metrics and logs allow an operator to detect abnormal spikes without exposing sensitive payment data.

Use both request-level assertions and an independent reconciliation oracle (for example, querying an authorized test ledger/export or using a test-only database check). Response status alone cannot prove idempotency because two duplicate requests may both return 2xx while incorrectly applying the credit twice.

### 11.4 Regression coverage across five country-specific rule variants

Avoid copying the entire suite five times. Use a **shared behavioral test suite plus country-specific configuration and a small number of country-specific tests**.

- Define a common set of country-neutral invariants: one invoice per lease/period, payment idempotency, no billing for prohibited lease states, correct event replay, financial reconciliation, and required response fields.
- Store country rules as data/configuration fixtures (for example, billing calendar, week boundary/time zone, currency, rounding policy, discount eligibility, tax/fee rules, and lease-specific exceptions). Do not hard-code country branching into each test.
- Parameterize shared tests over a country configuration matrix. Each run supplies the country code and relevant expected values; the same assertions run against all five variants.
- Maintain a small set of focused tests for genuinely unique country behavior, rather than duplicating common workflows.
- Use pairwise/decision-table coverage for interactions among country, billing schedule, discount eligibility, and boundary dates, then add exhaustive cases for high-risk financial rules.
- Include contract/schema tests to ensure country configuration changes do not accidentally alter the shared API contract.
- Run a fast PR suite on core invariants plus representative country variants, and a full five-country regression suite nightly and before release. Always run all five variants for changes to shared billing calculations, currency handling, calendars, discount logic, or event schemas.
- Version country-rule fixtures alongside the code and retain the configuration version or effective date used for a bill, so historical billing can be reproduced and audited after rules change.

A useful coverage matrix is:

| Coverage dimension | Shared suite | Country-specific data/tests |
|---|---|---|
| Billing calculation and invoice invariants | Same tests for all countries | Expected amounts, rounding, currency, taxes/fees as applicable |
| Billing week and due date | Same boundary-test logic | Country calendar, time zone, week start/cutoff |
| Discount eligibility | Same behavior assertions | Country-specific eligibility/configuration values |
| Payment idempotency and event replay | Same tests for all countries | Country context and ledger/reporting dimensions |
| Lease eligibility and status | Same tests for all countries | Only documented legal/contractual exceptions |
| Unique local requirements | Not applicable where behavior is identical | Dedicated tests only for genuinely unique rules |

This approach maximizes reuse while preserving country-specific risk coverage. It also prevents a shared test from passing merely because it uses one country's assumptions for all five variants.
