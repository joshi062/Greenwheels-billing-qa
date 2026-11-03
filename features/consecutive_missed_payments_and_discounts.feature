Feature: Consecutive Missed Payment Overdue Projection and Single-Week Discount Rules
  As the Greenwheels Finance and Fleet Operations Team
  I want the billing summary to accurately flag drivers with 3 consecutive missed payments as overdue and restrict discounts to the next cycle only
  So that default risk is surfaced reliably without over-discounting weekly leases

  Background:
    Given the core fleet operations event store is initialized
    And driver "drv_active_001" has an active motorcycle lease at a weekly rate of 4000 KES

  Scenario Outline: Project driver overdue status based on consecutive missed payments
    Given driver "<driver_id>" has a historical billing sequence of "<payment_history>"
    When the fleet ops system queries the billing summary for driver "<driver_id>"
    Then the summary reports a consecutive missed payment count of <consecutive_missed>
    And the driver summary account status is projected as "<projected_status>"
    And the total outstanding balance is <outstanding_kes> KES

    Examples:
      | driver_id      | payment_history                    | consecutive_missed | projected_status | outstanding_kes |
      | drv_hist_001   | PAID, MISSED, MISSED               | 2                  | active           | 8000            |
      | drv_hist_002   | PAID, MISSED, MISSED, MISSED       | 3                  | overdue          | 12000           |
      | drv_hist_003   | MISSED, MISSED, PAID, MISSED       | 1                  | active           | 12000           |
      | drv_hist_004   | MISSED, MISSED, MISSED, MISSED     | 4                  | overdue          | 16000           |

  Scenario Outline: Apply weekly discounts strictly to the next billing cycle without stacking or carry-over
    Given driver "drv_active_001" is currently in billing week 20
    And a valid discount of <first_discount> KES is applied for next billing week 21
    When an additional discount of <second_discount> KES is submitted for billing week 21
    And billing cycles are subsequently generated for week 21 and week 22 in "KES"
    Then the invoice amount_due for week 21 is <week_21_amount_due> KES
    And the invoice amount_due for week 22 reverts to the full base rate of <week_22_amount_due> KES

    Examples:
      | first_discount | second_discount | week_21_amount_due | week_22_amount_due |
      | 500            | 0               | 3500               | 4000               |
      | 500            | 500             | 3500               | 4000               |
      | 1000           | 400             | 3000               | 4000               |
