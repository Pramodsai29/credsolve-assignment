-- ============================================================================
-- CREDSOVLE DATA PLATFORM - DATA CLEANING & RECONCILIATION LAYER
-- ============================================================================
-- Description: Standardizes dirty raw tables, eliminates injected duplicates,
-- resolves entity collisions, normalizes timezones, and isolates dirty data.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. CLEAN BORROWERS (SCD Entity Resolution & Deduplication)
-- ----------------------------------------------------------------------------
-- Issue: 30,600 raw records for only 11,015 unique borrower_ids due to overwritten
-- profiles and 600 exact row duplicates.
-- Treatment: Deduplicate exact rows, rank by updated_at DESC, keep latest version.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE clean_borrowers AS
WITH deduped_borrowers AS (
    SELECT DISTINCT * FROM stg_borrowers
),
ranked_borrowers AS (
    SELECT 
        borrower_id,
        TRIM(name) as borrower_name,
        TRIM(phone) as phone_number,
        LOWER(TRIM(email)) as email_address,
        TRIM(city) as city,
        TRIM(state) as state,
        created_at,
        updated_at,
        ROW_NUMBER() OVER (
            PARTITION BY borrower_id 
            ORDER BY updated_at DESC, created_at DESC
        ) as entity_recency_rank
    FROM deduped_borrowers
    WHERE borrower_id IS NOT NULL
)
SELECT 
    borrower_id,
    borrower_name,
    phone_number,
    email_address,
    city,
    state,
    created_at,
    updated_at
FROM ranked_borrowers
WHERE entity_recency_rank = 1;

-- ----------------------------------------------------------------------------
-- 2. CLEAN AGENTS (License Seat Resolution)
-- ----------------------------------------------------------------------------
-- Issue: 30,000 rows for 1,000 agent licenses due to SCD audit trail.
-- Treatment: Deduplicate and select latest profile per agent_id.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE clean_agents AS
WITH deduped_agents AS (
    SELECT DISTINCT * FROM stg_agents
),
ranked_agents AS (
    SELECT 
        agent_id,
        employee_code,
        TRIM(agent_name) as agent_name,
        vendor_id,
        team,
        status as agent_status,
        joined_at,
        updated_at,
        ROW_NUMBER() OVER (
            PARTITION BY agent_id 
            ORDER BY updated_at DESC, joined_at DESC
        ) as agent_recency_rank
    FROM deduped_agents
    WHERE agent_id IS NOT NULL
)
SELECT 
    agent_id,
    employee_code,
    agent_name,
    vendor_id,
    team,
    agent_status,
    joined_at,
    updated_at
FROM ranked_agents
WHERE agent_recency_rank = 1;

-- ----------------------------------------------------------------------------
-- 3. CLEAN ACCOUNTS & ORPHAN ENRICHMENT
-- ----------------------------------------------------------------------------
-- Issue: 455 accounts have NULL borrower_id, and 2,458 accounts reference
-- non-existent borrowers in borrower master.
-- Treatment: Left join with clean_borrowers and create an explicit orphan flag.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE clean_accounts AS
SELECT 
    a.account_id,
    a.borrower_id,
    b.borrower_name,
    b.phone_number,
    b.city,
    b.state,
    a.loan_type,
    a.principal_amount,
    a.outstanding_amount,
    a.dpd,
    CASE 
        WHEN a.dpd < 30 THEN '1. DPD < 30'
        WHEN a.dpd < 60 THEN '2. DPD 30-59'
        WHEN a.dpd < 90 THEN '3. DPD 60-89'
        ELSE '4. DPD 90+'
    END as dpd_bucket,
    a.risk_segment,
    a.status as account_status,
    a.opened_at,
    a.timezone as account_timezone,
    CASE WHEN b.borrower_id IS NULL THEN 1 ELSE 0 END as is_orphan_account
FROM stg_accounts a
LEFT JOIN clean_borrowers b ON a.borrower_id = b.borrower_id;

-- ----------------------------------------------------------------------------
-- 4. CLEAN PAYMENTS (Deduplication & Transaction Ledger Hygiene)
-- ----------------------------------------------------------------------------
-- Issue: 486 exact row duplicates, 500 duplicate payment_ids, and 29.9% of
-- transaction volume sitting in FAILED, PENDING, or REVERSED states.
-- Treatment: Remove duplicates, calculate payment lag for retries, isolate SUCCESS.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE clean_payments AS
WITH deduped_raw_payments AS (
    SELECT DISTINCT * FROM stg_payments
),
ranked_payments AS (
    SELECT 
        payment_id,
        account_id,
        borrower_id,
        event_at,
        payment_reference,
        amount,
        payment_status,
        payment_method,
        provider_id,
        ROW_NUMBER() OVER (
            PARTITION BY payment_id 
            ORDER BY event_at ASC
        ) as payment_id_rank,
        LAG(event_at) OVER (
            PARTITION BY account_id, amount 
            ORDER BY event_at
        ) as prev_payment_time
    FROM deduped_raw_payments
    WHERE payment_id IS NOT NULL
)
SELECT 
    payment_id,
    account_id,
    borrower_id,
    event_at as event_at_raw,
    CAST(event_at AS TIMESTAMP) as event_at,
    strftime('%Y-%m', event_at) as payment_month,
    payment_reference,
    amount,
    payment_status,
    payment_method,
    provider_id,
    CASE WHEN payment_status = 'SUCCESS' THEN 1 ELSE 0 END as is_success,
    CASE 
        WHEN prev_payment_time IS NOT NULL 
         AND datediff('minute', prev_payment_time, event_at) <= 1440 
        THEN 1 ELSE 0 
    END as is_retry_transaction
FROM ranked_payments
WHERE payment_id_rank = 1;

-- ----------------------------------------------------------------------------
-- 5. CLEAN CALLS (Telephony Hygiene, Inactive Routes, Duration Sanity)
-- ----------------------------------------------------------------------------
-- Issue: 1,350 duplicate calls, 60.1% calls routed through INACTIVE vendors,
-- non-connected calls (BUSY, FAILED) recording 450s duration, calls at 2 AM.
-- Treatment: Deduplicate calls, sanitize talk duration (0s for non-connected),
-- flag inactive vendor routing and non-compliant hours.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE clean_calls AS
WITH deduped_calls AS (
    SELECT DISTINCT * FROM stg_calls
),
ranked_calls AS (
    SELECT 
        call_id,
        account_id,
        borrower_id,
        event_at,
        agent_id,
        campaign_id,
        direction,
        vendor_id,
        call_status,
        duration_sec as raw_duration_sec,
        CASE WHEN call_status = 'ANSWERED' THEN duration_sec ELSE 0 END as talk_duration_sec,
        timezone,
        ROW_NUMBER() OVER (
            PARTITION BY call_id 
            ORDER BY event_at ASC
        ) as call_rank
    FROM deduped_calls
    WHERE call_id IS NOT NULL
)
SELECT 
    rc.call_id,
    rc.account_id,
    rc.borrower_id,
    rc.event_at,
    rc.agent_id,
    rc.campaign_id,
    rc.direction,
    rc.vendor_id,
    vt.vendor_name,
    vt.status as vendor_configured_status,
    CASE WHEN vt.status = 'INACTIVE' THEN 1 ELSE 0 END as is_inactive_vendor_routed,
    rc.call_status,
    rc.raw_duration_sec,
    rc.talk_duration_sec,
    rc.timezone,
    extract(hour from rc.event_at) as call_hour,
    CASE WHEN extract(hour from rc.event_at) BETWEEN 8 AND 19 THEN 1 ELSE 0 END as is_rbi_compliant_hour
FROM ranked_calls rc
LEFT JOIN stg_vendor_telephony vt ON rc.vendor_id = vt.vendor_id
WHERE rc.call_rank = 1;

-- ----------------------------------------------------------------------------
-- 6. CLEAN DISPOSITIONS (Harmonized Disposition Ontology)
-- ----------------------------------------------------------------------------
-- Issue: Simultaneous coexistence of legacy 'PROMISE_TO_PAY' and modern 'PTP'.
-- Treatment: Unify into canonical operational statuses and compute RPC flag.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE clean_dispositions AS
SELECT 
    disposition_id,
    account_id,
    borrower_id,
    event_at,
    call_id,
    agent_id,
    disposition_code as raw_disposition_code,
    disposition_version,
    CASE 
        WHEN disposition_code IN ('PTP', 'PROMISE_TO_PAY') THEN 'PROMISE_TO_PAY'
        WHEN disposition_code = 'PTP_BROKEN' THEN 'PTP_BROKEN'
        WHEN disposition_code = 'PAID' THEN 'PAID'
        WHEN disposition_code = 'CALLBACK' THEN 'CALLBACK'
        WHEN disposition_code = 'DISPUTE' THEN 'DISPUTE'
        WHEN disposition_code = 'REFUSED' THEN 'REFUSED'
        WHEN disposition_code IN ('NO_CONTACT', 'WRONG_NUMBER') THEN 'UNREACHABLE'
        ELSE 'OTHER'
    END as canonical_disposition,
    CASE 
        WHEN disposition_code IN ('PTP', 'PROMISE_TO_PAY', 'PAID', 'CALLBACK', 'DISPUTE', 'REFUSED') 
        THEN 1 ELSE 0 
    END as is_right_party_contact_rpc
FROM (SELECT DISTINCT * FROM stg_call_dispositions);
