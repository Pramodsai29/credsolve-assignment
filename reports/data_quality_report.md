# DATA QUALITY & INTEGRITY REPORT: CREDSOVLE COLLECTIONS DATASET

**Document Version:** 1.0.0  
**Prepared For:** Leadership Team & Engineering Architecture Group  
**Status:** Certified Audit  
**Date:** October 30, 2026  

---

## 1. Executive Summary & Quality Funnel

An audit of 17 operational source datasets revealed severe data quality degradation across entity resolution, event deduplication, timezone alignment, vendor telephony routing, and financial reconciliation. Prior to this audit, historical business dashboards consumed raw tables directly, propagating false metrics to executive leadership.

### The Transformation Funnel: Raw Records → Rejected/Corrected → Golden Dataset

| Entity / Dataset | Raw Records | Exact Duplicates | Logic / Entity Corrections | Certified Golden Dataset | Rejection / Impact Description |
|:---|---:|---:|---:|---:|:---|
| **Borrowers** | 30,600 | 600 | 18,985 | **11,015** | Overwritten SCD records resolved; deduped to latest master profile. |
| **Accounts** | 30,000 | 0 | 2,913 | **30,000** | 2,913 orphan accounts flagged (missing borrower master). |
| **Agents** | 30,000 | 0 | 29,000 | **1,000** | 30k SCD audit rows collapsed into 1,000 unique agent licenses. |
| **Agent Sessions** | 15,000 | 0 | 0 | **15,000** | Session durations validated and cross-checked against call times. |
| **Campaigns** | 120 | 0 | 0 | **120** | Verified start/end dates and targeting rule versions. |
| **Daily Targeting** | 45,000 | 0 | 0 | **45,000** | Prioritization and recommended channels validated. |
| **Calls** | 91,350 | 1,271 | 79 | **90,000** | Deduplicated call_ids; sanitized 450s duration on failed calls. |
| **Call Attempts** | 120,000 | 0 | 0 | **120,000** | Verified dialer attempts and attempt sequence numbers. |
| **Call Dispositions**| 35,000 | 0 | 7,830 | **35,000** | Unified legacy `PROMISE_TO_PAY` and modern `PTP` codes. |
| **WhatsApp Events** | 60,600 | 600 | 0 | **60,000** | Deduplicated exact event records. |
| **SMS Events** | 45,000 | 0 | 0 | **45,000** | Delivery and click rates validated. |
| **Field Visits** | 25,000 | 0 | 0 | **25,000** | Visit outcomes and geolocation fields validated. |
| **Promises to Pay** | 18,000 | 0 | 4,343 | **18,000** | Identified 96.7% unverified "KEPT" promises lacking bank credit. |
| **Payments** | 25,500 | 486 | 7,480 | **25,000** | 500 duplicate IDs removed; segregated ₹575.8M non-cash statuses. |
| **Vendor Telephony** | 15 | 0 | 8 | **15** | Identified 8 INACTIVE vendors actively receiving live traffic. |
| **Complaints** | 8,000 | 0 | 0 | **8,000** | Escalation severity and resolution timestamps mapped. |
| **Status History** | 60,000 | 0 | 0 | **60,000** | Audited write-off and delinquency transition dates. |

---

## 2. In-Depth Forensic Analysis of Major Data Issues

### Issue 1: Gross Ledger Contamination & Duplicate Payments
- **Detection Methodology:** Ran frequency distribution of `payment_status` and analyzed `payment_id` uniqueness along with 24-hour proximity clustering on `(account_id, amount)`.
- **Finding:**
  1. 500 duplicate `payment_id` rows (486 exact row duplicates + 14 key collisions).
  2. ₹575,772,690.82 (29.9% of gross payment value) consists of `FAILED` (₹283.5M), `PENDING` (₹194.9M), and `REVERSED` (₹97.4M) transactions.
  3. 500 payment retries occurred within 24 hours of an earlier transaction of the identical amount.
- **Treatment:** Deduplicated by `payment_id` using event-timestamp ranking. Created explicit boolean flag `is_success = (payment_status == 'SUCCESS')`. Separated financial ledger reporting from transaction attempt logs.
- **Business Impact:** Eliminated **₹575.8 Million in phantom recovery** that was erroneously counted in historical business claims.

---

### Issue 2: Entity Resolution & 29x Row Multiplier Explosion
- **Detection Methodology:** Cross-entity cardinality testing: `COUNT(*)` vs `COUNT(DISTINCT agent_id)` and `COUNT(DISTINCT borrower_id)`.
- **Finding:**
  1. `stg_borrowers` has 30,600 rows for only 11,015 unique `borrower_id`s. Profiles had conflicting names and states across updated timestamps.
  2. `stg_agents` contains 30,000 rows for 1,000 `agent_id`s and 1,099 `employee_code`s.
  3. A naive SQL inner join between `calls` and `agents` exploded from 91,350 calls to **2,683,601 rows (29.4x multiplier)**.
- **Treatment:** Implemented SCD-2 window ranking: `ROW_NUMBER() OVER (PARTITION BY entity_id ORDER BY updated_at DESC) = 1` to resolve each entity to its latest master state.
- **Business Impact:** Prevents 2,900% over-reporting of agent productivity and prevents multi-row joins from corrupting dashboard aggregations.

---

### Issue 3: Inactive Telephony Gateways & Call Duration Distortion
- **Detection Methodology:** Left join between `stg_calls` and `stg_vendor_telephony` on `vendor_id`. Duration profiling grouped by `call_status`.
- **Finding:**
  1. 54,089 calls (60.1% of all calls) were routed through 8 telephony vendor accounts explicitly flagged as `status = 'INACTIVE'`.
  2. Calls with status `BUSY`, `FAILED`, `VOICEMAIL`, and `NO_ANSWER` recorded an average `duration_sec` of **451 seconds (~7.5 minutes)**, identical to answered calls.
- **Treatment:**
  1. Flagged `is_inactive_vendor_routed = 1` for vendor SLA penalties.
  2. Redefined talk duration: `talk_duration_sec = CASE WHEN call_status = 'ANSWERED' THEN duration_sec ELSE 0 END`.
- **Business Impact:** Uncovered that dialers were paying termination fees to defunct gateways with a 20% network drop rate. Corrected total productive agent talk time from 11,400 hours down to **2,280 actual talk hours**.

---

### Issue 4: Timezone Non-Standardization & Regulatory Hours Violation
- **Detection Methodology:** Hour-of-day histogram of `event_at` grouped by the `timezone` column (`Asia/Kolkata`, `UTC`, `Asia/Dubai`).
- **Finding:**
  1. Event timestamps were stored in unadjusted local wall-clock times without UTC offsets.
  2. 50.1% of collection calls occurred outside RBI compliant hours (8:00 AM – 7:00 PM IST). Over 2,500 calls were logged between 12:00 AM and 4:00 AM.
  3. Converting UTC payments to IST shifted 25–37 transactions (₹1.2M – ₹2.0M) across month-end cutoffs every month.
- **Treatment:** Standardized all timestamps to UTC as canonical storage format, with `event_at_ist` generated dynamically for regulatory compliance checks and executive reporting.
- **Business Impact:** Mitigated legal liability under RBI Fair Practices Code for collections, and prevented cross-month revenue slippage.

---

### Issue 5: Disposition Taxonomy Disconnect (PTP vs PROMISE_TO_PAY)
- **Detection Methodology:** Frequency distribution of `disposition_code` across `disposition_version` in `stg_call_dispositions`.
- **Finding:** Both `PROMISE_TO_PAY` (3,926 records) and `PTP` (3,904 records) coexisted across legacy, v1, and v2 schemas. Analysts filtering for `disposition_code = 'PTP'` were systematically omitting 50.1% of customer payment commitments.
- **Treatment:** Created a canonical mapping layer unifying `PTP` and `PROMISE_TO_PAY` into `PROMISE_TO_PAY`, and tagged genuine customer contacts as `is_right_party_contact_rpc = 1`.
- **Business Impact:** Doubled visibility of customer commitments and standardized RPC calculation across all dialer versions.

---

### Issue 6: Orphan Accounts (Denominator Leakage)
- **Detection Methodology:** Foreign key validation: `accounts.borrower_id` NOT IN `(SELECT borrower_id FROM borrowers)`.
- **Finding:** 2,913 loan accounts (9.7% of all accounts, representing ₹1.01 Billion in outstanding debt) have no corresponding record in the borrower master database.
- **Treatment:** Retained all 30,000 accounts in `golden_accounts` using `LEFT JOIN` and added an explicit quality flag: `is_orphan_account = 1`.
- **Business Impact:** Prevented silent loss of ₹1.01 Billion in debt exposure from portfolio recovery calculations.

---

## 3. Data Quality Rule Enforcement Matrix (dbt / Great Expectations)

| Table | Column | Expectation / Contract | Severity | Violation Count | Remediation in Pipeline |
|:---|:---|:---|:---:|---:|:---|
| `payments` | `payment_id` | `expect_column_values_to_be_unique` | Critical | 500 | Deduplicated via window rank |
| `payments` | `payment_status`| `expect_column_values_to_be_in_set(['SUCCESS'])` for recovery | Critical | 7,466 | Filtered by `is_success = 1` |
| `borrowers`| `borrower_id` | `expect_column_values_to_be_unique` | Critical | 19,585 | Deduplicated to latest updated_at |
| `calls` | `vendor_id` | `expect_column_values_to_be_active_vendor` | High | 54,089 | Tagged `is_inactive_vendor_routed` |
| `calls` | `event_at` | `expect_hour_to_be_between(8, 19)` | High | 45,103 | Tagged `is_rbi_compliant_hour` |
| `accounts` | `borrower_id` | `expect_foreign_key_to_exist(borrowers.borrower_id)` | High | 2,913 | Flagged `is_orphan_account` |
| `calls` | `duration_sec`| `expect_duration_zero_when_not_answered` | Medium | 73,204 | Zeroed out talk_duration_sec |
