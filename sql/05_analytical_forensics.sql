-- ============================================================================
-- CREDSOVLE DATA PLATFORM - FORENSICS & STATISTICAL AUDIT REPOSITORY
-- ============================================================================
-- Description: Diagnostic SQL scripts executing forensic tests A through G,
-- demonstrating Simpson's Paradox, and testing counterfactual targeting uplift.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- FORENSIC A: DUPLICATE PAYMENTS & STATUS CONTAMINATION
-- Question: Could retries or ingestion issues be inflating recovery?
-- ----------------------------------------------------------------------------
-- 1. Exact row duplicate audit in raw payments
SELECT 
    'Exact Row Duplicates' as audit_type,
    count(*) - count(distinct (payment_id, account_id, amount, event_at, payment_status, payment_reference)) as count_impact,
    null as amount_impact
FROM stg_payments
UNION ALL
-- 2. Duplicate payment_id collisions
SELECT 
    'Payment ID Collisions',
    count(*) - count(distinct payment_id),
    null
FROM stg_payments
UNION ALL
-- 3. Potential payment retries within 24 hours (same account & amount)
SELECT 
    'Payment Retries (<24h)',
    count(*),
    sum(amount)
FROM (
    SELECT payment_id, account_id, amount, event_at,
           LAG(event_at) OVER (PARTITION BY account_id, amount ORDER BY event_at) as prev_at
    FROM stg_payments
)
WHERE prev_at IS NOT NULL AND datediff('minute', prev_at, event_at) <= 1440
UNION ALL
-- 4. Status breakdown showing non-cash contamination
SELECT 
    'Non-Success Ingestion Contamination: ' || payment_status,
    count(*),
    sum(amount)
FROM stg_payments
WHERE payment_status != 'SUCCESS'
GROUP BY payment_status;


-- ----------------------------------------------------------------------------
-- FORENSIC B: ATTRIBUTION ERRORS & SELF-CURE LEAKAGE
-- Question: Are payments being incorrectly attributed to recent interactions?
-- ----------------------------------------------------------------------------
SELECT 
    attribution_window,
    count(*) as payment_count,
    sum(amount) as recovered_amount,
    round(sum(amount) * 100.0 / sum(sum(amount)) over(), 2) as pct_of_total_recovery,
    CASE 
        WHEN attribution_window IN ('WINDOW_0_24H', 'WINDOW_24_72H', 'WINDOW_3_7D') 
        THEN 'Actionable Operational Attribution'
        ELSE 'Fictitious / Organic Self-Cure'
    END as attribution_validity
FROM golden_payment_attribution
GROUP BY 1
ORDER BY recovered_amount DESC;


-- ----------------------------------------------------------------------------
-- FORENSIC C: TIMEZONE ANOMALY & MONTH-END SHIFTS
-- Question: Are calls and payments shifting into the wrong hour/day?
-- ----------------------------------------------------------------------------
-- 1. Uniform 24/7 call distribution across night hours (Regulatory breach)
SELECT 
    timezone,
    CASE 
        WHEN extract(hour from event_at) BETWEEN 0 AND 5 THEN '1. Late Night (00:00 - 06:00)'
        WHEN extract(hour from event_at) BETWEEN 6 AND 7 THEN '2. Early Morning (06:00 - 08:00)'
        WHEN extract(hour from event_at) BETWEEN 8 AND 19 THEN '3. Compliant Window (08:00 - 19:00)'
        ELSE '4. Late Evening (19:00 - 24:00)'
    END as time_window,
    count(*) as call_volume,
    round(count(*) * 100.0 / sum(count(*)) over(partition by timezone), 2) as pct_volume
FROM golden_calls
GROUP BY 1, 2
ORDER BY 1, 2;

-- 2. Payments shifting month boundaries when adjusted to IST (+5:30)
SELECT 
    strftime('%Y-%m', event_at_raw) as raw_month,
    strftime('%Y-%m', event_at_raw + interval '5 hours 30 minutes') as ist_month,
    count(*) as transaction_count,
    sum(amount) as shifted_recovery_amount
FROM golden_payments
WHERE strftime('%Y-%m', event_at_raw) != strftime('%Y-%m', event_at_raw + interval '5 hours 30 minutes')
  AND is_success = 1
GROUP BY 1, 2
ORDER BY 1;


-- ----------------------------------------------------------------------------
-- FORENSIC D: VENDOR MAPPING & INACTIVE GATEWAY LEAKAGE
-- Question: Did telephony response codes change, and are inactive vendors used?
-- ----------------------------------------------------------------------------
SELECT 
    v.vendor_name,
    v.status as configured_status,
    v.schema_version,
    count(c.call_id) as total_routed_calls,
    count(case when c.call_status = 'ANSWERED' then 1 end) as answered_calls,
    count(case when c.call_status = 'FAILED' then 1 end) as failed_calls,
    round(count(case when c.call_status = 'FAILED' then 1 end) * 100.0 / count(c.call_id), 2) as failure_rate_pct
FROM stg_vendor_telephony v
LEFT JOIN golden_calls c ON v.vendor_id = c.vendor_id
GROUP BY 1, 2, 3
ORDER BY total_routed_calls DESC;


-- ----------------------------------------------------------------------------
-- FORENSIC E: AGENT IDENTITY COLLISION & DIALER SEAT REUSE
-- Question: Does the same agent appear under multiple identifiers?
-- ----------------------------------------------------------------------------
SELECT 
    'Agent IDs with Multiple Employee Codes' as metric,
    count(*) as affected_entities
FROM (
    SELECT agent_id FROM stg_agents GROUP BY agent_id HAVING count(distinct employee_code) > 1
)
UNION ALL
SELECT 
    'Employee Codes with Multiple Agent IDs',
    count(*)
FROM (
    SELECT employee_code FROM stg_agents GROUP BY employee_code HAVING count(distinct agent_id) > 1
);


-- ----------------------------------------------------------------------------
-- FORENSIC F & SIMPSON'S PARADOX: PORTFOLIO MIX & DPD STRATIFICATION
-- Question: Did performance improve because of population mix shifts?
-- ----------------------------------------------------------------------------
SELECT 
    loan_type,
    dpd_bucket,
    risk_segment,
    count(*) as account_count,
    sum(outstanding_amount) as total_outstanding,
    sum(total_recovered_amount) as total_recovered,
    round(sum(total_recovered_amount) * 100.0 / sum(outstanding_amount), 2) as recovery_rate_pct
FROM transformed_account_summary
GROUP BY 1, 2, 3
ORDER BY 1, 2, 3;


-- ----------------------------------------------------------------------------
-- FORENSIC G: DENOMINATOR MANIPULATION & ORPHAN ACCOUNTS
-- Question: Are accounts disappearing from the denominator?
-- ----------------------------------------------------------------------------
SELECT 
    CASE 
        WHEN is_orphan_account = 1 THEN 'Orphan Account (Missing Borrower)'
        ELSE 'Valid Linked Account'
    END as account_category,
    count(*) as num_accounts,
    sum(outstanding_amount) as total_debt_exposure,
    sum(total_recovered_amount) as total_recovered,
    round(sum(total_recovered_amount) * 100.0 / sum(outstanding_amount), 2) as recovery_rate_pct
FROM transformed_account_summary
GROUP BY 1;


-- ----------------------------------------------------------------------------
-- COUNTERFACTUAL AUDIT: TARGETED VS UNTARGETED ACCOUNTS (UPLIFT TEST)
-- Question: What would recovery have looked like if targeting had not changed?
-- ----------------------------------------------------------------------------
SELECT 
    CASE WHEN dt.account_id IS NOT NULL THEN 'Targeted Population (Treatment)' ELSE 'Untargeted Population (Control)' END as cohort,
    count(distinct a.account_id) as total_accounts,
    count(distinct case when p.is_success = 1 then a.account_id end) as paying_accounts,
    round(count(distinct case when p.is_success = 1 then a.account_id end) * 100.0 / count(distinct a.account_id), 2) as payer_conversion_rate_pct,
    sum(a.outstanding_amount) as total_outstanding,
    sum(case when p.is_success = 1 then p.amount else 0 end) as total_recovered,
    round(sum(case when p.is_success = 1 then p.amount else 0 end) * 100.0 / sum(a.outstanding_amount), 2) as recovery_rate_pct
FROM clean_accounts a
LEFT JOIN (SELECT distinct account_id FROM stg_daily_targeting) dt ON a.account_id = dt.account_id
LEFT JOIN golden_payments p ON a.account_id = p.account_id
GROUP BY 1;
