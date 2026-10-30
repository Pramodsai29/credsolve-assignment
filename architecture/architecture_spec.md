# Production Architecture Specification & Engineering Guide

This document is the engineering companion specification to `production_architecture.svg` and `reports/architecture_design.md`.

## Summary Architecture Highlights:
1. **Medallion Pipeline**:
   - `Bronze (Raw)`: Immutable Parquet files stored on object storage.
   - `Silver (Clean)`: DuckDB / Delta Lake SQL transformations executing deduplication, entity resolution, and data quality assertions.
   - `Gold (Dimensional)`: Star schema (`dim_accounts`, `dim_borrowers`, `dim_agents`, `fact_payments`, `fact_interactions`, `bridge_payment_attribution`).
2. **Key Mathematical Standards**:
   - `Daily Run Rate`: Normalizes monthly payments by calendar days ($N_{\text{days}}$) to remove February/March 10.7% calendar distortion.
   - `Operational Attribution Window`: Bounded to 168 hours (7 days) to eliminate organic self-cure misattribution.
   - `Talk Duration Sanitation`: Zeroes duration on non-connected calls (`BUSY`, `FAILED`, `NO_ANSWER`, `VOICEMAIL`).
3. **Automated Data Quality & Observability**:
   - Pre-merge checks on primary keys.
   - PagerDuty alerting on inactive vendor routing.
   - Z-score anomaly monitors for daily transaction drops.
