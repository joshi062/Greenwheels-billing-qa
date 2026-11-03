# Greenwheels Bike — Billing Cycle Quality Strategy & Automation Suite

This repository contains the Quality Engineering strategy, API test automation suite (Postman/Newman), BDD feature specifications (Gherkin), defect reports, and GitHub Actions CI pipeline for the **Greenwheels Bike Core Fleet Operations Billing Cycle** microservice.

---

## Repository Structure

```text
.
├── .github/workflows/qa.yml     # CI pipeline running Newman
├── features/                    # Cucumber/Gherkin BDD specifications for core business rules
│   ├── lease_state_billing_guard.feature
│   └── consecutive_missed_payments_and_discounts.feature
├── postman/
│   ├── collection.json          # Postman v2.1 API test suite (Happy paths, 5 Business Rules, 5 Negative cases)
│   └── env.json                 # Environment configuration with safe placeholder values
├── AI_USAGE.md                  # Transparent log of AI usage, corrections, and manual additions
├── DEFECTS.md                   # Root-cause defect reports for the two intentional stub defects
├── TEST_PLAN.md                 # End-to-end test strategy, event-sourcing approach & 500k scale design
└── README.md                    # Setup, execution instructions, assumptions, and known gaps
```

---

## Prerequisites

Ensure the following tools are installed locally:
* **Docker & Docker Compose** (v2.x+) — to run the Billing Cycle stub service and PostgreSQL backend
* **Node.js** (v18+ or v20+) & **npm** — to execute Newman and Gherkin linters
* **Newman CLI** — install globally via:
  ```bash
  npm install -g newman newman-reporter-junitfull
  ```

---

## Setup & Execution Steps

### 1. Start the Stub Service
From the root of the repository (where `docker-compose.yml` is located), start the service in detached mode:

```bash
docker compose up -d
```

Verify the service is healthy and responding within the 5-second SLA:
```bash
curl -i --max-time 5 http://localhost:8000/billing/summary/drv_active_001
```

### 2. Execute the Newman API Test Suite
Run the Postman v2.1 collection against the local environment configuration:

```bash
newman run postman/collection.json \
  --environment postman/env.json \
  --timeout-request 5000 \
  --reporters cli,json,junitfull \
  --reporter-json-export newman-results.json \
  --reporter-junitfull-export newman-results.xml
```

### 3. Lint Gherkin Feature Files (Optional)
To verify that all `.feature` files in `features/` adhere to standard Cucumber syntax:

```bash
npx gherkin-lint features/
```

### 4. Tear Down Environment
To stop the containers and wipe ephemeral volumes so subsequent test runs start from a clean event store:

```bash
docker compose down -v
```

---

## Key Assumptions

1. **Seeded Driver Fixtures in Stub Service:**
   The test suite assumes the `docker-compose.yml` stub environment initializes distinct driver archetypes mapped in `postman/env.json`:
   * `drv_active_001`: Active lease in good standing (base weekly rate: `4000 KES`).
   * `drv_paused_002`: Lease currently in `paused` state.
   * `drv_terminated_003`: Lease currently in `terminated` state.
   * `drv_overdue_004`: Active lease with 3 consecutive missed payments.
2. **Synchronous Projection in the Stub Environment:**
   We assume the local Docker stub projects events into the `GET /billing/cycles/{driver_id}` and `GET /billing/summary/{driver_id}` views synchronously or within `< 100ms`, allowing immediate read-after-write verification in Newman.
3. **Authentication:**
   The collection passes a standard Bearer token (`{{auth_token}}`) via the `Authorization` header using a non-sensitive placeholder value (`PLACEHOLDER_BEARER_TOKEN_FOR_CI`).
4. **Intentional Stub Defects:**
   Because the stub service contains two intentional defects (documented in `DEFECTS.md`), running `newman run` against the unpatched stub will intentionally fail on the specific business-rule assertions designed to catch those defects.

---

## Known Gaps & Future Enhancements

1. **Asynchronous Eventual-Consistency Polling:**
   In Newman, read-model verification executes immediately after the write request. In a multi-node production environment with asynchronous projection workers, tests should implement a bounded retry/polling helper.
2. **True Parallel Concurrency Testing in Newman:**
   Newman executes requests sequentially. Catching sub-millisecond race conditions requires concurrent thread execution (addressed in our Scale Test Strategy in `TEST_PLAN.md` Section 7.3 using JMeter/k6/pytest-xdist).
3. **Step Definition Implementation:**
   Per the specification, `features/` contains lintable Gherkin feature specifications (`Scenario Outline` + `Examples` + `Background`) without underlying Python `pytest-bdd` or `behave` step definitions.
4. **Direct Event-Store Schema Contract Checks:**
   Adding direct schema validation against raw events emitted to PostgreSQL/EventBridge to ensure internal event contracts never drift across microservices.
