-- ============================================================================
-- CREDSOVLE DATA PLATFORM - RAW DDL LAYER (STAGING)
-- ============================================================================
-- Description: Raw table definitions matching incoming CSV extracts from telephony,
-- CRM, payment gateway, and core banking systems.
-- ============================================================================

-- 1. Borrowers Master (SCD Type-2 Raw Extract)
CREATE TABLE IF NOT EXISTS stg_borrowers (
    borrower_id VARCHAR,
    name VARCHAR,
    phone VARCHAR,
    email VARCHAR,
    city VARCHAR,
    state VARCHAR,
    created_at TIMESTAMP,
    updated_at TIMESTAMP
);

-- 2. Accounts Master (Loan accounts)
CREATE TABLE IF NOT EXISTS stg_accounts (
    account_id VARCHAR PRIMARY KEY,
    borrower_id VARCHAR,
    loan_type VARCHAR,
    principal_amount DOUBLE,
    outstanding_amount DOUBLE,
    dpd BIGINT,
    risk_segment VARCHAR,
    status VARCHAR,
    opened_at TIMESTAMP,
    timezone VARCHAR,
    schema_version VARCHAR
);

-- 3. Telephony & CRM Agents
CREATE TABLE IF NOT EXISTS stg_agents (
    agent_id VARCHAR,
    employee_code VARCHAR,
    agent_name VARCHAR,
    vendor_id VARCHAR,
    team VARCHAR,
    status VARCHAR,
    joined_at TIMESTAMP,
    updated_at TIMESTAMP
);

-- 4. Agent Login Sessions
CREATE TABLE IF NOT EXISTS stg_agent_sessions (
    session_id VARCHAR PRIMARY KEY,
    agent_id VARCHAR,
    login_at TIMESTAMP,
    channel VARCHAR,
    device_id VARCHAR,
    timezone VARCHAR,
    logout_at TIMESTAMP
);

-- 5. Collection Campaigns
CREATE TABLE IF NOT EXISTS stg_campaigns (
    campaign_id VARCHAR PRIMARY KEY,
    campaign_name VARCHAR,
    channel VARCHAR,
    strategy_version VARCHAR,
    start_at TIMESTAMP,
    target_definition VARCHAR,
    end_at TIMESTAMP
);

-- 6. Daily Targeting Allocation
CREATE TABLE IF NOT EXISTS stg_daily_targeting (
    target_id VARCHAR PRIMARY KEY,
    account_id VARCHAR,
    campaign_id VARCHAR,
    target_date DATE,
    priority BIGINT,
    recommended_channel VARCHAR,
    status VARCHAR
);

-- 7. Voice Calls Log
CREATE TABLE IF NOT EXISTS stg_calls (
    call_id VARCHAR,
    account_id VARCHAR,
    borrower_id VARCHAR,
    event_at TIMESTAMP,
    agent_id VARCHAR,
    campaign_id VARCHAR,
    direction VARCHAR,
    vendor_id VARCHAR,
    call_status VARCHAR,
    duration_sec BIGINT,
    timezone VARCHAR
);

-- 8. Dialer Call Attempts
CREATE TABLE IF NOT EXISTS stg_call_attempts (
    attempt_id VARCHAR PRIMARY KEY,
    account_id VARCHAR,
    borrower_id VARCHAR,
    event_at TIMESTAMP,
    call_id VARCHAR,
    agent_id VARCHAR,
    attempt_no BIGINT,
    vendor_id VARCHAR,
    attempt_status VARCHAR
);

-- 9. Call Dispositions & Agent Wrap-up
CREATE TABLE IF NOT EXISTS stg_call_dispositions (
    disposition_id VARCHAR PRIMARY KEY,
    account_id VARCHAR,
    borrower_id VARCHAR,
    event_at TIMESTAMP,
    call_id VARCHAR,
    agent_id VARCHAR,
    disposition_code VARCHAR,
    disposition_version VARCHAR
);

-- 10. WhatsApp Digital Events
CREATE TABLE IF NOT EXISTS stg_whatsapp_events (
    whatsapp_event_id VARCHAR,
    account_id VARCHAR,
    borrower_id VARCHAR,
    event_at TIMESTAMP,
    message_id VARCHAR,
    event_type VARCHAR,
    template_code VARCHAR,
    provider_id VARCHAR
);

-- 11. SMS Gateway Events
CREATE TABLE IF NOT EXISTS stg_sms_events (
    sms_event_id VARCHAR PRIMARY KEY,
    account_id VARCHAR,
    borrower_id VARCHAR,
    event_at TIMESTAMP,
    message_id VARCHAR,
    event_type VARCHAR,
    template_code VARCHAR,
    provider_id VARCHAR
);

-- 12. Field Agent Visits
CREATE TABLE IF NOT EXISTS stg_field_visits (
    visit_id VARCHAR PRIMARY KEY,
    account_id VARCHAR,
    borrower_id VARCHAR,
    event_at TIMESTAMP,
    agent_id VARCHAR,
    visit_type VARCHAR,
    outcome VARCHAR,
    latitude DOUBLE,
    longitude DOUBLE,
    scheduled_at TIMESTAMP
);

-- 13. Promises to Pay (PTP)
CREATE TABLE IF NOT EXISTS stg_promises_to_pay (
    ptp_id VARCHAR PRIMARY KEY,
    account_id VARCHAR,
    borrower_id VARCHAR,
    event_at TIMESTAMP,
    agent_id VARCHAR,
    promised_amount DOUBLE,
    promised_date DATE,
    status VARCHAR,
    source VARCHAR
);

-- 14. Payment Transactions & Bank Ingestion
CREATE TABLE IF NOT EXISTS stg_payments (
    payment_id VARCHAR,
    account_id VARCHAR,
    borrower_id VARCHAR,
    event_at TIMESTAMP,
    payment_reference VARCHAR,
    amount DOUBLE,
    payment_status VARCHAR,
    payment_method VARCHAR,
    provider_id VARCHAR
);

-- 15. Telephony Vendors Configuration
CREATE TABLE IF NOT EXISTS stg_vendor_telephony (
    vendor_id VARCHAR PRIMARY KEY,
    vendor_name VARCHAR,
    vendor_account_id VARCHAR,
    timezone VARCHAR,
    status VARCHAR,
    schema_version VARCHAR
);

-- 16. Customer Complaints & Grievance Logs
CREATE TABLE IF NOT EXISTS stg_complaints (
    complaint_id VARCHAR PRIMARY KEY,
    account_id VARCHAR,
    borrower_id VARCHAR,
    event_at TIMESTAMP,
    complaint_type VARCHAR,
    severity VARCHAR,
    status VARCHAR,
    source VARCHAR,
    resolution_at TIMESTAMP
);

-- 17. Account Status Audit History
CREATE TABLE IF NOT EXISTS stg_account_status_history (
    history_id VARCHAR PRIMARY KEY,
    account_id VARCHAR,
    borrower_id VARCHAR,
    event_at TIMESTAMP,
    status VARCHAR,
    changed_by VARCHAR,
    source VARCHAR,
    recorded_at TIMESTAMP
);
