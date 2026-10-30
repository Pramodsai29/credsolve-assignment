-- ============================================================================
-- CREDSOVLE DATA PLATFORM - TRANSFORMATIONS & AT-SCALE ANALYTICS LAYER
-- ============================================================================
-- Description: Transforms cleaned data into dimensional Golden tables, builds
-- omnichannel unified events, and establishes multi-touch attribution logic.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. UNIFIED OMNICHANNEL INTERACTION FEED (Voice, WhatsApp, SMS, Field)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE transformed_interactions AS
-- Channel: Voice
SELECT 
    call_id as interaction_id,
    account_id,
    borrower_id,
    'VOICE' as channel,
    event_at,
    call_status as event_type,
    CASE WHEN call_status = 'ANSWERED' THEN 1 ELSE 0 END as is_connected,
    talk_duration_sec as engagement_value,
    3.50 as estimated_unit_cost_inr
FROM clean_calls
UNION ALL
-- Channel: WhatsApp
SELECT 
    whatsapp_event_id as interaction_id,
    account_id,
    borrower_id,
    'WHATSAPP' as channel,
    event_at,
    event_type,
    CASE WHEN event_type IN ('READ', 'REPLIED', 'PAYMENT_CLICK') THEN 1 ELSE 0 END as is_connected,
    CASE WHEN event_type = 'PAYMENT_CLICK' THEN 1 ELSE 0 END as engagement_value,
    0.45 as estimated_unit_cost_inr
FROM (SELECT DISTINCT * FROM stg_whatsapp_events)
UNION ALL
-- Channel: SMS
SELECT 
    sms_event_id as interaction_id,
    account_id,
    borrower_id,
    'SMS' as channel,
    event_at,
    event_type,
    CASE WHEN event_type IN ('DELIVERED', 'CLICKED') THEN 1 ELSE 0 END as is_connected,
    CASE WHEN event_type = 'CLICKED' THEN 1 ELSE 0 END as engagement_value,
    0.15 as estimated_unit_cost_inr
FROM (SELECT DISTINCT * FROM stg_sms_events)
UNION ALL
-- Channel: Field Visits
SELECT 
    visit_id as interaction_id,
    account_id,
    borrower_id,
    'FIELD' as channel,
    event_at,
    outcome as event_type,
    CASE WHEN outcome IN ('CONTACTED', 'PAID', 'PTP') THEN 1 ELSE 0 END as is_connected,
    CASE WHEN outcome = 'PAID' THEN 1 ELSE 0 END as engagement_value,
    250.00 as estimated_unit_cost_inr
FROM (SELECT DISTINCT * FROM stg_field_visits);

-- ----------------------------------------------------------------------------
-- 2. PAYMENT MULTI-WINDOW ATTRIBUTION ENGINE
-- ----------------------------------------------------------------------------
-- Computes the time elapsed between the payment and the preceding customer
-- interaction on the account.
-- Windows:
--   - 0 to 24 Hours: Immediate direct touch conversion
--   - 24 to 72 Hours: Follow-up touch conversion
--   - 3 to 7 Days: Operational window (industry benchmark)
--   - 7 to 30 Days: Loose attribution / lagging conversion
--   - > 30 Days: Expired touch / Organic self-cure
--   - No Touch: 100% Pure Organic Self-Cure
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE transformed_payment_attribution AS
WITH ranked_touches AS (
    SELECT 
        p.payment_id,
        p.account_id,
        p.borrower_id,
        p.amount,
        p.event_at as payment_time,
        i.interaction_id,
        i.channel as last_touch_channel,
        i.event_type as last_touch_type,
        i.event_at as last_touch_time,
        datediff('second', i.event_at, p.event_at) / 3600.0 as hours_since_last_touch,
        ROW_NUMBER() OVER (
            PARTITION BY p.payment_id 
            ORDER BY i.event_at DESC
        ) as touch_rank
    FROM clean_payments p
    LEFT JOIN transformed_interactions i 
      ON p.account_id = i.account_id 
     AND i.event_at <= p.event_at
    WHERE p.is_success = 1
)
SELECT 
    payment_id,
    account_id,
    borrower_id,
    amount,
    payment_time,
    last_touch_channel,
    last_touch_type,
    last_touch_time,
    hours_since_last_touch,
    CASE 
        WHEN hours_since_last_touch IS NULL THEN 'ORGANIC_NO_TOUCH'
        WHEN hours_since_last_touch <= 24.0 THEN 'WINDOW_0_24H'
        WHEN hours_since_last_touch <= 72.0 THEN 'WINDOW_24_72H'
        WHEN hours_since_last_touch <= 168.0 THEN 'WINDOW_3_7D'
        WHEN hours_since_last_touch <= 720.0 THEN 'WINDOW_7_30D'
        ELSE 'WINDOW_GT_30D'
    END as attribution_window_bucket,
    CASE 
        WHEN hours_since_last_touch IS NOT NULL AND hours_since_last_touch <= 168.0 
        THEN 1 ELSE 0 
    END as is_valid_operational_attribution
FROM ranked_touches
WHERE touch_rank = 1;

-- ----------------------------------------------------------------------------
-- 3. ACCOUNT 360 BEHAVIORAL PROFILE
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE transformed_account_summary AS
WITH pay_summary AS (
    SELECT 
        account_id,
        count(distinct payment_id) as total_payments,
        sum(case when is_success = 1 then amount else 0 end) as total_recovered_amount,
        max(case when is_success = 1 then event_at end) as last_payment_date
    FROM clean_payments
    GROUP BY 1
),
touch_summary AS (
    SELECT 
        account_id,
        count(*) as total_touches,
        sum(case when channel = 'VOICE' then 1 else 0 end) as voice_calls_count,
        sum(case when channel = 'WHATSAPP' then 1 else 0 end) as whatsapp_count,
        sum(case when channel = 'SMS' then 1 else 0 end) as sms_count,
        sum(case when channel = 'FIELD' then 1 else 0 end) as field_visits_count,
        sum(estimated_unit_cost_inr) as total_collection_cost_inr
    FROM transformed_interactions
    GROUP BY 1
),
ptp_summary AS (
    SELECT 
        account_id,
        count(*) as total_ptps_logged,
        sum(case when status = 'KEPT' then 1 else 0 end) as ptps_kept
    FROM stg_promises_to_pay
    GROUP BY 1
)
SELECT 
    a.account_id,
    a.borrower_id,
    a.borrower_name,
    a.loan_type,
    a.principal_amount,
    a.outstanding_amount,
    a.dpd,
    a.dpd_bucket,
    a.risk_segment,
    a.account_status,
    a.is_orphan_account,
    COALESCE(p.total_recovered_amount, 0) as total_recovered_amount,
    COALESCE(p.total_recovered_amount, 0) * 1.0 / a.outstanding_amount as account_recovery_rate,
    CASE WHEN COALESCE(p.total_recovered_amount, 0) > 0 THEN 1 ELSE 0 END as has_recovered,
    COALESCE(t.total_touches, 0) as total_touches,
    COALESCE(t.voice_calls_count, 0) as voice_calls_count,
    COALESCE(t.whatsapp_count, 0) as whatsapp_count,
    COALESCE(t.sms_count, 0) as sms_count,
    COALESCE(t.field_visits_count, 0) as field_visits_count,
    COALESCE(t.total_collection_cost_inr, 0) as total_collection_cost_inr,
    COALESCE(pt.total_ptps_logged, 0) as total_ptps_logged,
    COALESCE(pt.ptps_kept, 0) as ptps_kept
FROM clean_accounts a
LEFT JOIN pay_summary p ON a.account_id = p.account_id
LEFT JOIN touch_summary t ON a.account_id = t.account_id
LEFT JOIN ptp_summary pt ON a.account_id = pt.account_id;
