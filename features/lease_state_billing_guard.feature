Feature: Lease State Guard and Currency Enforcement on Billing Cycle Generation
  As the Greenwheels Fleet Operations Billing Service
  I want to prevent billing cycles from being generated for non-active leases or non-KES currencies
  So that drivers on paused or terminated leases are never wrongfully billed and ledger currency stays uniform

  Background:
    Given the core fleet operations event store is initialized
    And the base weekly motorcycle lease rate is 4000 KES

  Scenario Outline: Enforce lease state eligibility when generating a weekly billing cycle
    Given driver "<driver_id>" has a motorcycle lease currently in the "<lease_state>" state
    When the billing engine requests a new billing cycle for driver "<driver_id>" for week <week_number> in "KES"
    Then the billing service responds with HTTP status <http_status>
    And the billing cycle generation outcome is "<outcome>"
    And the number of new BillingCycleGenerated facts recorded for "<driver_id>" is <facts_emitted>

    Examples:
      | driver_id          | lease_state | week_number | http_status | outcome                        | facts_emitted |
      | drv_active_001     | active      | 14          | 201         | invoice_generated              | 1             |
      | drv_paused_002     | paused      | 14          | 409         | rejected_lease_paused          | 0             |
      | drv_terminated_003 | terminated  | 14          | 409         | rejected_lease_terminated      | 0             |

  Scenario Outline: Validate strict KES currency requirement on billing cycle write requests
    Given driver "drv_active_001" has a motorcycle lease currently in the "active" state
    When the billing engine requests a new billing cycle for driver "drv_active_001" for week 15 in "<currency>"
    Then the billing service responds with HTTP status <http_status>
    And the currency validation outcome is "<validation_result>"

    Examples:
      | currency | http_status | validation_result            |
      | KES      | 201         | accepted_valid_currency      |
      | INR      | 400         | rejected_unsupported_INR     |
      | NPR      | 400         | rejected_unsupported_NPR     |
      | USD      | 400         | rejected_unsupported_USD     |
