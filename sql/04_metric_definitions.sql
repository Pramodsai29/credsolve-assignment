-- ============================================================================
-- CREDSOVLE DATA PLATFORM - METRIC DEFINITIONS & SEMANTIC LAYER
-- ============================================================================
-- Description: Standardized, production-grade KPI formulations challenging the
-- flawed legacy business definitions.
-- ============================================================================

-- ============================================================================
-- METRIC 1: CONTACT RATE
-- ----------------------------------------------------------------------------
-- Flawed Legacy Definition:
--   Answered Calls / Total Dialed Attempts
--   Problems: Conflates telco network failures with borrower reachability, counts
--   voicemails/auto-attendants as contacts, and ignores unique customer reach.
--
-- Robust CredSolve Definition:
--   Unique Borrowers Reached on Valid Calls / Unique Borrowers Dialed
--   Excludes telco drops/gateway errors to measure true operational reachability.
-- ============================================================================
CREATE OR REPLACE VIEW metric_contact_rate AS
SELECT 
    strftime('%Y-%m', event_at) as month,
    -- Legacy Metric
    count(case when call_status = 'ANSWERED' then 1 end) * 1.0 / count(*) as legacy_contact_rate,
    -- CredSolve Robust Account-Level Reach Rate
    count(distinct case when call_status = 'ANSWERED' then account_id end) * 1.0 
        / count(distinct account_id) as robust_unique_reach_rate,
    -- CredSolve Clean Connected Rate (excluding network failed routes)
    count(case when call_status = 'ANSWERED' then 1 end) * 1.0 
        / count(case when call_status != 'FAILED' then 1 end) as telephony_delivery_contact_rate
FROM golden_calls
GROUP BY 1
ORDER BY 1;

-- ============================================================================
-- METRIC 2: RIGHT PARTY CONTACT (RPC) RATE
-- ----------------------------------------------------------------------------
-- Flawed Legacy Definition:
--   Dispositions tagged as 'RPC' / Total Dispositions
--   Problems: Agents dispositioned RPC on busy/failed calls; counted third-party
--   callbacks or disputes as RPC; missed 'PROMISE_TO_PAY' due to version code splits.
--
-- Robust CredSolve Definition:
--   Verified Verified Borrower Engagements on Connected Calls / Total Connected Calls
-- ============================================================================
CREATE OR REPLACE VIEW metric_rpc_rate AS
SELECT 
    strftime('%Y-%m', c.event_at) as month,
    count(case when c.call_status = 'ANSWERED' and cd.is_right_party_contact_rpc = 1 then 1 end) as verified_rpcs,
    count(case when c.call_status = 'ANSWERED' then 1 end) as connected_calls,
    count(case when c.call_status = 'ANSWERED' and cd.is_right_party_contact_rpc = 1 then 1 end) * 1.0
        / nullif(count(case when c.call_status = 'ANSWERED' then 1 end), 0) as robust_rpc_rate
FROM golden_calls c
LEFT JOIN golden_dispositions cd ON c.call_id = cd.call_id
GROUP BY 1
ORDER BY 1;

-- ============================================================================
-- METRIC 3: PROMISE-TO-PAY (PTP) RATE
-- ----------------------------------------------------------------------------
-- Flawed Legacy Definition:
--   Promises Logged / Total Calls
--   Problems: Misses legacy 'PROMISE_TO_PAY' code; dilutes rate by including
--   unconnected call attempts where no borrower was present.
--
-- Robust CredSolve Definition:
--   Total Commitments Secured (PTP + PROMISE_TO_PAY) / Verified RPCs
-- ============================================================================
CREATE OR REPLACE VIEW metric_ptp_rate AS
SELECT 
    strftime('%Y-%m', c.event_at) as month,
    count(case when cd.canonical_disposition = 'PROMISE_TO_PAY' then 1 end) as ptps_secured,
    count(case when cd.is_right_party_contact_rpc = 1 then 1 end) as total_rpcs,
    count(case when cd.canonical_disposition = 'PROMISE_TO_PAY' then 1 end) * 1.0
        / nullif(count(case when cd.is_right_party_contact_rpc = 1 then 1 end), 0) as robust_ptp_rate_on_rpc
FROM golden_calls c
JOIN golden_dispositions cd ON c.call_id = cd.call_id
WHERE c.call_status = 'ANSWERED'
GROUP BY 1
ORDER BY 1;

-- ============================================================================
-- METRIC 4: PTP KEPT RATE
-- ----------------------------------------------------------------------------
-- Flawed Legacy Definition:
--   PTP table status = 'KEPT' / Total PTP table entries
--   Problems: Operates on unverified agent self-reported clicks; 97% of 'KEPT'
--   records have no matching ledger payment within ±7 days.
--
-- Robust CredSolve Definition:
--   PTPs with Verified Bank Ingestion SUCCESS Payment within [-3, +7] Days / Total PTPs
-- ============================================================================
CREATE OR REPLACE VIEW metric_ptp_kept_rate AS
WITH ptp_payment_verification AS (
    SELECT 
        ptp.ptp_id,
        ptp.account_id,
        ptp.event_at as ptp_date,
        ptp.promised_amount,
        ptp.promised_date,
        ptp.status as agent_reported_status,
        max(case when p.payment_id is not null and p.is_success = 1 then 1 else 0 end) as is_verified_by_ledger,
        coalesce(sum(case when p.is_success = 1 then p.amount else 0 end), 0) as actual_paid_amount
    FROM stg_promises_to_pay ptp
    LEFT JOIN golden_payments p 
      ON ptp.account_id = p.account_id
     AND p.event_at >= ptp.event_at
     AND datediff('day', ptp.promised_date, p.event_at) BETWEEN -3 AND 7
    GROUP BY 1, 2, 3, 4, 5, 6
)
SELECT 
    strftime('%Y-%m', ptp_date) as month,
    count(*) as total_ptps_logged,
    count(case when agent_reported_status = 'KEPT' then 1 end) as agent_reported_kept_count,
    count(case when agent_reported_status = 'KEPT' then 1 end) * 1.0 / count(*) as flawed_legacy_kept_rate,
    count(case when is_verified_by_ledger = 1 then 1 end) as ledger_verified_kept_count,
    count(case when is_verified_by_ledger = 1 then 1 end) * 1.0 / count(*) as robust_ledger_verified_kept_rate
FROM ptp_payment_verification
GROUP BY 1
ORDER BY 1;

-- ============================================================================
-- METRIC 5: RECOVERY RATE
-- ----------------------------------------------------------------------------
-- Flawed Legacy Definition:
--   Sum(Raw Payment Amount) / Total Current Outstanding
--   Problems: Distorted by calendar days in month (March 31d vs Feb 28d = 10.7% artifact),
--   includes FAILED and PENDING payments, and includes duplicate retries.
--
-- Robust CredSolve Definition:
--   Daily Run Rate = Verified SUCCESS Deduplicated Amount / Calendar Days in Month
--   And Closed-Book Cohort Recovery = Cumulative Collected / Opening Balance.
-- ============================================================================
CREATE OR REPLACE VIEW metric_recovery_rate AS
WITH cal_days AS (
    SELECT '2026-01' as month, 31 as days UNION ALL
    SELECT '2026-02', 28 UNION ALL
    SELECT '2026-03', 31 UNION ALL
    SELECT '2026-04', 30 UNION ALL
    SELECT '2026-05', 31 UNION ALL
    SELECT '2026-06', 30 UNION ALL
    SELECT '2026-07', 31 UNION ALL
    SELECT '2026-08', 8
)
SELECT 
    cd.month,
    cd.days as calendar_days,
    -- Flawed Raw Monthly Total
    sum(p.amount) as flawed_raw_monthly_recovery,
    (sum(p.amount) - LAG(sum(p.amount)) OVER (ORDER BY cd.month)) * 100.0 
        / LAG(sum(p.amount)) OVER (ORDER BY cd.month) as flawed_raw_mom_growth,
    -- Robust Verified Clean Success Monthly Total
    sum(case when p.is_success = 1 then p.amount else 0 end) as robust_clean_monthly_recovery,
    (sum(case when p.is_success = 1 then p.amount else 0 end) 
        - LAG(sum(case when p.is_success = 1 then p.amount else 0 end)) OVER (ORDER BY cd.month)) * 100.0
        / LAG(sum(case when p.is_success = 1 then p.amount else 0 end)) OVER (ORDER BY cd.month) as clean_success_mom_growth,
    -- Robust Calendar-Normalized Daily Run Rate (True Underlying Trend)
    sum(case when p.is_success = 1 then p.amount else 0 end) / cd.days as robust_daily_recovery_run_rate,
    ((sum(case when p.is_success = 1 then p.amount else 0 end) / cd.days)
        - LAG(sum(case when p.is_success = 1 then p.amount else 0 end) / cd.days) OVER (ORDER BY cd.month)) * 100.0
        / LAG(sum(case when p.is_success = 1 then p.amount else 0 end) / cd.days) OVER (ORDER BY cd.month) as robust_daily_run_rate_growth_pct
FROM cal_days cd
JOIN golden_payments p ON cd.month = p.payment_month
GROUP BY 1, 2
ORDER BY 1;

-- ============================================================================
-- METRIC 6: RECOVERY PER AGENT-HOUR
-- ----------------------------------------------------------------------------
-- Flawed Legacy Definition:
--   Total Payments / Total Dialer Call Duration
--   Problems: Duration was non-zero (450s) even for busy/failed calls, inflating
--   agent time and understating true hourly productivity.
--
-- Robust CredSolve Definition:
--   Verified Operationally-Attributed Recovery / Total Human Session Hours Logged
-- ============================================================================
CREATE OR REPLACE VIEW metric_recovery_per_agent_hour AS
WITH agent_hours AS (
    SELECT 
        strftime('%Y-%m', login_at) as month,
        sum(datediff('second', login_at, logout_at)) / 3600.0 as human_session_hours
    FROM stg_agent_sessions
    GROUP BY 1
),
monthly_clean_pay AS (
    SELECT 
        payment_month as month,
        sum(case when is_success = 1 then amount else 0 end) as total_success_recovery
    FROM golden_payments
    GROUP BY 1
),
attributed_clean_pay AS (
    SELECT 
        strftime('%Y-%m', payment_at) as month,
        sum(amount) as attributed_recovery_7d
    FROM golden_payment_attribution
    WHERE is_operationally_attributed = 1
    GROUP BY 1
)
SELECT 
    ah.month,
    ah.human_session_hours,
    mp.total_success_recovery,
    ap.attributed_recovery_7d,
    -- Flawed Un-attributed productivity
    mp.total_success_recovery / ah.human_session_hours as gross_recovery_per_agent_hour,
    -- Robust Attributed productivity
    ap.attributed_recovery_7d / ah.human_session_hours as true_attributed_recovery_per_agent_hour
FROM agent_hours ah
JOIN monthly_clean_pay mp ON ah.month = mp.month
LEFT JOIN attributed_clean_pay ap ON ah.month = ap.month
ORDER BY 1;

-- ============================================================================
-- METRIC 7: COST PER ₹ RECOVERED & CHANNEL ROI
-- ----------------------------------------------------------------------------
-- Flawed Legacy Definition:
--   Monthly Call Center Budget / Total Monthly Inflow
--   Problems: Ignores digital and field costs, assumes all recovery was caused
--   by the call center, ignoring the 80% organic self-cure rate.
--
-- Robust CredSolve Definition:
--   Total Channel Operating Cost / Verified Attributed Recovery (7-Day Window)
-- ============================================================================
CREATE OR REPLACE VIEW metric_cost_per_rupee_recovered AS
WITH channel_costs AS (
    SELECT 
        channel,
        count(*) as total_touches,
        sum(channel_cost_inr) as total_channel_cost_inr
    FROM golden_interactions
    GROUP BY 1
),
channel_attributed_recovery AS (
    SELECT 
        last_touch_channel as channel,
        count(*) as attributed_payment_count,
        sum(amount) as attributed_recovered_amount
    FROM golden_payment_attribution
    WHERE is_operationally_attributed = 1
    GROUP BY 1
)
SELECT 
    cc.channel,
    cc.total_touches,
    cc.total_channel_cost_inr,
    COALESCE(ar.attributed_payment_count, 0) as attributed_payments,
    COALESCE(ar.attributed_recovered_amount, 0) as attributed_recovery_inr,
    cc.total_channel_cost_inr / nullif(ar.attributed_recovered_amount, 0) as cost_per_rupee_recovered,
    ar.attributed_recovered_amount / nullif(cc.total_channel_cost_inr, 0) as recovery_multiplier_roi
FROM channel_costs cc
LEFT JOIN channel_attributed_recovery ar ON cc.channel = ar.channel
ORDER BY recovery_multiplier_roi DESC;
