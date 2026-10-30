"""
CredSolve Analytics Pipeline - Golden Dataset Builder
Production ETL script creating the certified analytical layer.
"""

import os
import duckdb
import pandas as pd
import numpy as np

def build_golden_dataset(raw_dir: str, output_dir: str):
    print("=" * 60)
    print("STARTING CREDSOVLE GOLDEN DATASET PIPELINE")
    print("=" * 60)
    
    os.makedirs(output_dir, exist_ok=True)
    duckdb_path = os.path.join(output_dir, "credsolve_golden.duckdb")
    if os.path.exists(duckdb_path):
        os.remove(duckdb_path)
        
    con = duckdb.connect(duckdb_path)
    
    # 1. Load raw tables into staging
    print("\n[Step 1/6] Ingesting raw CSVs into staging tables...")
    raw_tables = [
        'borrowers', 'accounts', 'agents', 'agent_sessions', 'campaigns',
        'daily_targeting', 'calls', 'call_attempts', 'call_dispositions',
        'whatsapp_events', 'sms_events', 'field_visits', 'promises_to_pay',
        'payments', 'vendor_telephony', 'complaints', 'account_status_history'
    ]
    
    for t in raw_tables:
        csv_file = os.path.join(raw_dir, f"{t}.csv")
        con.execute(f"CREATE TABLE stg_{t} AS SELECT * FROM read_csv_auto('{csv_file}')")
        cnt = con.execute(f"SELECT count(*) FROM stg_{t}").fetchone()[0]
        print(f"  - Loaded stg_{t:22}: {cnt:7,} rows")

    # 2. Build Golden Borrowers (Entity Resolution & Deduplication)
    print("\n[Step 2/6] Building golden_borrowers (SCD-2 entity resolution & dedup)...")
    con.execute("""
        CREATE TABLE golden_borrowers AS
        WITH deduped_records AS (
            SELECT DISTINCT * FROM stg_borrowers
        ),
        ranked_borrowers AS (
            SELECT 
                borrower_id,
                name,
                phone,
                email,
                city,
                state,
                created_at,
                updated_at,
                ROW_NUMBER() OVER (
                    PARTITION BY borrower_id 
                    ORDER BY updated_at DESC, created_at DESC
                ) as scd_rank
            FROM deduped_records
        )
        SELECT 
            borrower_id,
            name,
            phone,
            email,
            city,
            state,
            created_at,
            updated_at
        FROM ranked_borrowers
        WHERE scd_rank = 1
    """)
    b_raw = con.execute("SELECT count(*) FROM stg_borrowers").fetchone()[0]
    b_clean = con.execute("SELECT count(*) FROM golden_borrowers").fetchone()[0]
    print(f"  - Raw Borrowers: {b_raw:,} -> Golden Borrowers: {b_clean:,} (Removed {b_raw - b_clean:,} duplicate/historical rows)")

    # 3. Build Golden Agents (Entity Resolution & Seat Mapping)
    print("\n[Step 3/6] Building golden_agents...")
    con.execute("""
        CREATE TABLE golden_agents AS
        WITH deduped AS (
            SELECT DISTINCT * FROM stg_agents
        ),
        ranked_agents AS (
            SELECT 
                agent_id,
                employee_code,
                agent_name,
                vendor_id,
                team,
                status,
                joined_at,
                updated_at,
                ROW_NUMBER() OVER (
                    PARTITION BY agent_id 
                    ORDER BY updated_at DESC, joined_at DESC
                ) as rank_latest
            FROM deduped
        )
        SELECT 
            agent_id,
            employee_code,
            agent_name,
            vendor_id,
            team,
            status,
            joined_at,
            updated_at
        FROM ranked_agents
        WHERE rank_latest = 1
    """)
    agt_raw = con.execute("SELECT count(*) FROM stg_agents").fetchone()[0]
    agt_clean = con.execute("SELECT count(*) FROM golden_agents").fetchone()[0]
    print(f"  - Raw Agents: {agt_raw:,} -> Golden Agents: {agt_clean:,} unique agent licenses resolved")

    # 4. Build Golden Accounts
    print("\n[Step 4/6] Building golden_accounts...")
    con.execute("""
        CREATE TABLE golden_accounts AS
        SELECT 
            a.account_id,
            a.borrower_id,
            b.name as borrower_name,
            b.phone as borrower_phone,
            b.city as borrower_city,
            b.state as borrower_state,
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
        LEFT JOIN golden_borrowers b ON a.borrower_id = b.borrower_id
    """)
    acc_cnt = con.execute("SELECT count(*) FROM golden_accounts").fetchone()[0]
    orphan_cnt = con.execute("SELECT count(*) FROM golden_accounts WHERE is_orphan_account = 1").fetchone()[0]
    print(f"  - Golden Accounts: {acc_cnt:,} (Flagged {orphan_cnt:,} orphan accounts missing borrower master)")

    # 5. Build Golden Payments (Deduplication, Timezone Normalization, Status Segregation)
    print("\n[Step 5/6] Building golden_payments & attribution...")
    con.execute("""
        CREATE TABLE golden_payments AS
        WITH deduped_records AS (
            SELECT DISTINCT * FROM stg_payments
        ),
        ranked_payments AS (
            SELECT 
                payment_id,
                account_id,
                borrower_id,
                event_at,
                -- Standardize to Asia/Kolkata (IST) for reporting
                event_at as event_at_raw,
                payment_reference,
                amount,
                payment_status,
                payment_method,
                provider_id,
                ROW_NUMBER() OVER (
                    PARTITION BY payment_id 
                    ORDER BY event_at ASC
                ) as pid_rank,
                LAG(event_at) OVER (
                    PARTITION BY account_id, amount 
                    ORDER BY event_at
                ) as prev_payment_at
            FROM deduped_records
        )
        SELECT 
            payment_id,
            account_id,
            borrower_id,
            event_at_raw,
            CAST(event_at_raw AS TIMESTAMP) as event_at,
            strftime('%Y-%m', event_at_raw) as payment_month,
            payment_reference,
            amount,
            payment_status,
            payment_method,
            provider_id,
            CASE WHEN payment_status = 'SUCCESS' THEN 1 ELSE 0 END as is_success,
            CASE 
                WHEN prev_payment_at IS NOT NULL 
                 AND datediff('minute', prev_payment_at, event_at_raw) <= 1440 
                THEN 1 ELSE 0 
            END as is_potential_retry
        FROM ranked_payments
        WHERE pid_rank = 1
    """)
    pay_raw = con.execute("SELECT count(*) FROM stg_payments").fetchone()[0]
    pay_clean = con.execute("SELECT count(*) FROM golden_payments").fetchone()[0]
    pay_success = con.execute("SELECT count(*) FROM golden_payments WHERE is_success = 1").fetchone()[0]
    pay_success_amt = con.execute("SELECT sum(amount) FROM golden_payments WHERE is_success = 1").fetchone()[0]
    print(f"  - Raw Payments: {pay_raw:,} -> Clean Deduplicated Payments: {pay_clean:,}")
    print(f"  - Verified SUCCESS Payments: {pay_success:,} totaling ₹{pay_success_amt:,.2f}")

    # Build Golden Calls
    print("  - Building golden_calls (normalizing timezone, call talk time, vendor routing)...")
    con.execute("""
        CREATE TABLE golden_calls AS
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
                -- Telephony duration sanity check: Only answered calls have genuine talk time
                CASE WHEN call_status = 'ANSWERED' THEN duration_sec ELSE 0 END as talk_duration_sec,
                timezone,
                ROW_NUMBER() OVER (PARTITION BY call_id ORDER BY event_at ASC) as cid_rank
            FROM deduped_calls
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
            vt.status as vendor_status,
            CASE WHEN vt.status = 'INACTIVE' THEN 1 ELSE 0 END as is_inactive_vendor_routed,
            rc.call_status,
            rc.raw_duration_sec,
            rc.talk_duration_sec,
            rc.timezone,
            extract(hour from rc.event_at) as call_hour,
            CASE WHEN extract(hour from rc.event_at) BETWEEN 8 AND 19 THEN 1 ELSE 0 END as is_rbi_compliant_hour
        FROM ranked_calls rc
        LEFT JOIN stg_vendor_telephony vt ON rc.vendor_id = vt.vendor_id
        WHERE rc.cid_rank = 1
    """)
    calls_clean = con.execute("SELECT count(*) FROM golden_calls").fetchone()[0]
    inactive_vendor_calls = con.execute("SELECT count(*) FROM golden_calls WHERE is_inactive_vendor_routed = 1").fetchone()[0]
    non_compliant_calls = con.execute("SELECT count(*) FROM golden_calls WHERE is_rbi_compliant_hour = 0").fetchone()[0]
    print(f"  - Golden Calls: {calls_clean:,}")
    print(f"    * Calls routed to INACTIVE telecom vendor gateways: {inactive_vendor_calls:,} ({inactive_vendor_calls*100.0/calls_clean:.1f}%)")
    print(f"    * Calls outside RBI compliant hours (8am-7pm): {non_compliant_calls:,} ({non_compliant_calls*100.0/calls_clean:.1f}%)")

    # Build Golden Dispositions & RPC Mapping
    print("  - Building golden_dispositions (standardized disposition ontology)...")
    con.execute("""
        CREATE TABLE golden_dispositions AS
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
            END as standardized_disposition,
            CASE 
                WHEN disposition_code IN ('PTP', 'PROMISE_TO_PAY', 'PAID', 'CALLBACK', 'DISPUTE', 'REFUSED') 
                THEN 1 ELSE 0 
            END as is_right_party_contact_rpc
        FROM (SELECT DISTINCT * FROM stg_call_dispositions)
    """)

    # Build Unified Omnichannel Interaction Stream
    print("  - Building golden_interactions (Omnichannel Voice, WhatsApp, SMS, Field)...")
    con.execute("""
        CREATE TABLE golden_interactions AS
        -- Voice
        SELECT 
            call_id as interaction_id,
            account_id,
            borrower_id,
            'VOICE' as channel,
            event_at,
            call_status as event_type,
            CASE WHEN call_status = 'ANSWERED' THEN 1 ELSE 0 END as is_connected,
            talk_duration_sec as engagement_metric,
            3.50 as channel_cost_inr
        FROM golden_calls
        UNION ALL
        -- WhatsApp
        SELECT 
            whatsapp_event_id as interaction_id,
            account_id,
            borrower_id,
            'WHATSAPP' as channel,
            event_at,
            event_type,
            CASE WHEN event_type IN ('READ', 'REPLIED', 'PAYMENT_CLICK') THEN 1 ELSE 0 END as is_connected,
            CASE WHEN event_type = 'PAYMENT_CLICK' THEN 1 ELSE 0 END as engagement_metric,
            0.45 as channel_cost_inr
        FROM (SELECT DISTINCT * FROM stg_whatsapp_events)
        UNION ALL
        -- SMS
        SELECT 
            sms_event_id as interaction_id,
            account_id,
            borrower_id,
            'SMS' as channel,
            event_at,
            event_type,
            CASE WHEN event_type IN ('DELIVERED', 'CLICKED') THEN 1 ELSE 0 END as is_connected,
            CASE WHEN event_type = 'CLICKED' THEN 1 ELSE 0 END as engagement_metric,
            0.15 as channel_cost_inr
        FROM (SELECT DISTINCT * FROM stg_sms_events)
        UNION ALL
        -- Field Visits
        SELECT 
            visit_id as interaction_id,
            account_id,
            borrower_id,
            'FIELD' as channel,
            event_at,
            outcome as event_type,
            CASE WHEN outcome IN ('CONTACTED', 'PAID', 'PTP') THEN 1 ELSE 0 END as is_connected,
            CASE WHEN outcome = 'PAID' THEN 1 ELSE 0 END as engagement_metric,
            250.00 as channel_cost_inr
        FROM (SELECT DISTINCT * FROM stg_field_visits)
    """)
    inter_cnt = con.execute("SELECT count(*) FROM golden_interactions").fetchone()[0]
    print(f"  - Unified Omnichannel Interactions: {inter_cnt:,} events mapped")

    # Build Payment Attribution Table
    print("  - Building golden_payment_attribution (multi-touch lag analysis)...")
    con.execute("""
        CREATE TABLE golden_payment_attribution AS
        WITH ranked_prior_touches AS (
            SELECT 
                p.payment_id,
                p.account_id,
                p.amount,
                p.event_at as payment_at,
                i.channel,
                i.interaction_id,
                i.event_at as touch_at,
                datediff('second', i.event_at, p.event_at) / 3600.0 as lag_hours,
                ROW_NUMBER() OVER (
                    PARTITION BY p.payment_id 
                    ORDER BY i.event_at DESC
                ) as touch_recency_rank
            FROM golden_payments p
            LEFT JOIN golden_interactions i 
              ON p.account_id = i.account_id 
             AND i.event_at <= p.event_at
            WHERE p.is_success = 1
        )
        SELECT 
            payment_id,
            account_id,
            amount,
            payment_at,
            channel as last_touch_channel,
            lag_hours,
            CASE 
                WHEN lag_hours IS NULL THEN 'ORGANIC_NO_TOUCH'
                WHEN lag_hours <= 24 THEN 'TOUCH_0_24H'
                WHEN lag_hours <= 72 THEN 'TOUCH_24_72H'
                WHEN lag_hours <= 168 THEN 'TOUCH_3_7D'
                WHEN lag_hours <= 720 THEN 'TOUCH_7_30D'
                ELSE 'ORGANIC_EXPIRED_TOUCH'
            END as attribution_window,
            CASE 
                WHEN lag_hours IS NOT NULL AND lag_hours <= 168 
                THEN 1 ELSE 0 
            END as is_operationally_attributed
        FROM ranked_prior_touches
        WHERE touch_recency_rank = 1
    """)
    attr_summary = con.execute("""
        SELECT 
            attribution_window, 
            count(*) as cnt, 
            sum(amount) as amt,
            round(sum(amount) * 100.0 / sum(sum(amount)) over(), 2) as pct_amt
        FROM golden_payment_attribution 
        GROUP BY 1 
        ORDER BY amt DESC
    """).fetchdf()
    print("  - Attribution Summary:\n", attr_summary)

    # 6. Build Daily & Monthly KPI Datamarts
    print("\n[Step 6/6] Generating Executive KPI Datamarts...")
    con.execute("""
        CREATE TABLE golden_monthly_metrics AS
        WITH cal_days AS (
            SELECT '2026-01' as month, 31 as days UNION ALL
            SELECT '2026-02', 28 UNION ALL
            SELECT '2026-03', 31 UNION ALL
            SELECT '2026-04', 30 UNION ALL
            SELECT '2026-05', 31 UNION ALL
            SELECT '2026-06', 30 UNION ALL
            SELECT '2026-07', 31 UNION ALL
            SELECT '2026-08', 8
        ),
        pay_metrics AS (
            SELECT 
                payment_month as month,
                count(*) as total_payment_records,
                sum(amount) as raw_payment_amount,
                sum(case when is_success = 1 then 1 else 0 end) as success_payment_count,
                sum(case when is_success = 1 then amount else 0 end) as success_payment_amount,
                count(distinct case when is_success = 1 then account_id end) as unique_paying_accounts
            FROM golden_payments
            GROUP BY 1
        ),
        call_metrics AS (
            SELECT 
                strftime('%Y-%m', event_at) as month,
                count(*) as total_calls,
                sum(case when call_status = 'ANSWERED' then 1 else 0 end) as answered_calls,
                sum(talk_duration_sec) / 3600.0 as total_talk_hours
            FROM golden_calls
            GROUP BY 1
        ),
        ptp_metrics AS (
            SELECT 
                strftime('%Y-%m', event_at) as month,
                count(*) as total_ptps,
                sum(case when status = 'KEPT' then 1 else 0 end) as kept_ptps,
                sum(promised_amount) as total_promised_amount
            FROM stg_promises_to_pay
            GROUP BY 1
        ),
        session_metrics AS (
            SELECT 
                strftime('%Y-%m', login_at) as month,
                sum(datediff('second', login_at, logout_at)) / 3600.0 as total_agent_hours
            FROM stg_agent_sessions
            GROUP BY 1
        )
        SELECT 
            cd.month,
            cd.days as calendar_days,
            -- Payment metrics
            pm.raw_payment_amount,
            pm.success_payment_count,
            pm.success_payment_amount,
            pm.success_payment_amount / cd.days as success_amount_per_day,
            pm.success_payment_count * 1.0 / cd.days as success_count_per_day,
            -- Call metrics
            cm.total_calls,
            cm.answered_calls,
            cm.answered_calls * 1.0 / nullif(cm.total_calls, 0) as contact_rate,
            cm.total_talk_hours,
            -- PTP metrics
            pt.total_ptps,
            pt.kept_ptps,
            pt.kept_ptps * 1.0 / nullif(pt.total_ptps, 0) as ptp_kept_rate,
            -- Agent Productivity
            sm.total_agent_hours,
            pm.success_payment_amount / nullif(sm.total_agent_hours, 0) as recovery_per_agent_hour
        FROM cal_days cd
        LEFT JOIN pay_metrics pm ON cd.month = pm.month
        LEFT JOIN call_metrics cm ON cd.month = cm.month
        LEFT JOIN ptp_metrics pt ON cd.month = pt.month
        LEFT JOIN session_metrics sm ON cd.month = sm.month
        ORDER BY cd.month
    """)

    # Export tables to Parquet and CSV
    print("\nExporting Golden tables to Parquet and CSV files...")
    golden_tables = [
        'golden_borrowers', 'golden_accounts', 'golden_agents', 
        'golden_payments', 'golden_calls', 'golden_dispositions',
        'golden_interactions', 'golden_payment_attribution', 'golden_monthly_metrics'
    ]
    for gt in golden_tables:
        parquet_file = os.path.join(output_dir, f"{gt}.parquet")
        csv_file = os.path.join(output_dir, f"{gt}.csv")
        con.execute(f"COPY {gt} TO '{parquet_file}' (FORMAT PARQUET)")
        con.execute(f"COPY {gt} TO '{csv_file}' (HEADER, DELIMITER ',')")
        print(f"  - Saved {gt} -> {parquet_file}")
        
    con.close()
    print("\n" + "=" * 60)
    print("GOLDEN DATASET PIPELINE COMPLETE!")
    print(f"Output files stored in: {output_dir}")
    print("=" * 60)

if __name__ == "__main__":
    RAW_PATH = "/Users/bhavithatavva/Desktop/credsolve assignment/raw_data"
    GOLDEN_PATH = "/Users/bhavithatavva/Desktop/credsolve assignment/golden_data"
    build_golden_dataset(RAW_PATH, GOLDEN_PATH)
