# Greenwheels Bike — Billing Cycle Service Defect Report

## Defect 1: Duplicate `payment_reference` Records Duplicate Payment Facts and Double-Credits Driver Balance

* **Defect ID:** `DEF-BILL-001`
* **Title:** `POST /billing/payments` is not idempotent by `payment_reference`, resulting in duplicate credits in `GET /billing/summary/{driver_id}`
* **Steps to Reproduce:**
  1. Start the billing stub service via `docker compose up -d`.
  2. Generate a weekly billing cycle for an active driver:
     `POST /billing/cycles` with `{"driver_id": "drv_active_001", "week_number": 10, "currency": "KES"}` (returns `invoice_id: "inv_101"`, `amount_due: 4000`).
  3. Submit a valid payment fact:
     `POST /billing/payments` with `{"driver_id": "drv_active_001", "invoice_id": "inv_101", "payment_reference": "PAY-REF-HP-1001", "amount": 4000, "currency": "KES"}`.
  4. Re-submit the exact same payload with `"payment_reference": "PAY-REF-HP-1001"` a second time.
  5. Query `GET /billing/summary/drv_active_001`.
* **Expected Result:**
  The second `POST /billing/payments` request with `"payment_reference": "PAY-REF-HP-1001"` must be treated idempotently (returning `200 OK` without appending a new fact, or `409 Conflict`). In `GET /billing/summary/drv_active_001`, `total_paid` must remain `4000` KES and `total_outstanding` must remain `0` KES.
* **Actual Result:**
  The second `POST /billing/payments` request appends a second `PaymentFactRecorded` event to the store. Querying `GET /billing/summary/drv_active_001` shows `total_paid: 8000` and `total_outstanding: -4000`, double-crediting the driver's lease account.
* **Severity & Priority:**
  * **Severity:** **Critical (Sev-1)** — Direct financial ledger corruption; network retries or webhook replays over-credit driver equity and accelerate lease ownership without actual cash collection.
  * **Priority:** **P0 (Immediate Blocker)** — Must be fixed before release sign-off.
* **Suggested Root Cause:**
  The payment command handler appends the `PaymentFact` event to the event store without checking whether an existing event with the same `payment_reference` has already been committed (and/or lacks a `UNIQUE` constraint on `payment_reference` in the PostgreSQL event table).

---

## Defect 2: Discounts Stack/Carry Over OR Non-KES Currency / Paused Lease Accepted on Write Endpoints

* **Defect ID:** `DEF-BILL-002`
* **Title:** `POST /billing/cycles` and `POST /billing/discounts` fail to enforce domain state/discount/currency guards (allows stacking discounts or billing paused leases)
* **Steps to Reproduce:**
  1. Start the billing stub service via `docker compose up -d`.
  2. Apply a discount of `400 KES` for `drv_active_001` via `POST /billing/discounts`.
  3. Apply a second discount of `400 KES` for `drv_active_001` in the same cycle via `POST /billing/discounts` (or generate a billing cycle for `drv_paused_002` whose lease state is `paused`).
  4. Generate the next week's billing cycle via `POST /billing/cycles` for week `12`, followed by week `13`.
* **Expected Result:**
  Discounts must apply strictly to the following week's cycle (`amount_due: 3600` KES for week 12) without stacking (`3200` KES) and must reset to the base rate (`4000` KES) in week 13; similarly, any request to generate a cycle for a `paused` lease must be rejected with `400/409`.
* **Actual Result:**
  The service stacks multiple discount events onto the same billing cycle (reducing `amount_due` by `800` KES instead of `400` KES) and/or fails to mark the discount fact as consumed after week 12, carrying the discount into week 13 (or generates an active invoice for a `paused` lease).
* **Severity & Priority:**
  * **Severity:** **High (Sev-2)** — Causes systematic under-billing across weekly cycles or wrongful invoicing of drivers whose motorcycles are paused in maintenance.
  * **Priority:** **P1 (High — Release Blocker)** — Directly violates core billing cycle business rules.
* **Suggested Root Cause:**
  The billing cycle projector aggregates all `DiscountApplied` facts using a cumulative `SUM()` without filtering by target week or marking prior discount facts as consumed once a cycle is generated.
