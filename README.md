# CredSolve Collections Analytics & Forensic Investigation

> **Author:** Pramod Sai Tavva ([@Pramodsai29](https://github.com/Pramodsai29))  
> **Email:** pramodsaitavva31@gmail.com  
> **Status:** Certified Complete, Fully Reproducible, Production-Ready  
> **Dataset:** 17 relational collections datasets (30,000 accounts, ₹10,500 Cr outstanding debt, 12 months)  

---

## Executive Overview: The 4 Mission Answers

### 1. What Happened?
- **The 11% Month-on-Month recovery surge reported by the business is an illusion.**
- Reconstructing actual performance over the 12-month period demonstrates that **daily collections were completely flat at ~₹6.15M to ₹6.23M per day** across all months.
- The reported 11% increase (+10.99%) occurred exclusively between February 2026 (₹174.10M across 28 days = ₹6.218M/day) and March 2026 (₹193.23M across 31 days = ₹6.233M/day). When normalized for calendar days, **the true underlying change was +0.25%**. In April (30 days), collections immediately dropped by **-7.66%**.
- **Metrics genuinely improving:** None. Operational recovery rates, contact rates (19.8% ± 0.5%), and PTP kept rates (24.8% ± 0.6%) were statically flat.
- **Metrics that are misleading:** Gross recovery totals (distorted by 28 vs 31 calendar days), agent recovery per hour (distorted by non-zero duration on failed calls), and self-reported PTP kept rates (96.7% unverified against bank credits).

### 2. Why Did It Happen? (Forensic Root Causes)
1. **Gross Ledger Contamination (Fact):** ₹575.8M (29.9% of gross payment value) consists of `FAILED`, `PENDING`, and `REVERSED` attempts included in raw dashboards.
2. **Ghost Attribution (Fact):** 79.8% of recovered funds represent organic self-cures (no touch within 7 days). Only 20.2% of recovery occurred within 7 days of customer contact.
3. **Telephony Routing to Inactive Gateways (Fact):** 60.1% of collection calls (54,089 calls) were routed to telephony vendor accounts configured as `INACTIVE`, causing a constant 20% network failure rate.
4. **Regulatory Breach (Fact):** 50.1% of calls occurred outside RBI hours (8 AM – 7 PM IST), including ~2,500 calls at 2 AM due to unadjusted UTC/Dubai timestamp ingestion.
5. **Entity Overwrites & Row Multipliers (Fact):** 30,600 raw borrower records resolved to 11,015 unique borrowers; 30,000 raw agent rows resolved to 1,000 licenses. Naive joins caused a 29x row explosion.
6. **Simpson's Paradox (Strong Evidence):** Stratifying recovery across DPD brackets (<30, 30-59, 60-89, 90+) and loan products (Auto, BNPL, Consumer, Cards, Personal) reveals an identical recovery rate between 12.5% and 13.5% across all cohorts.
7. **Zero Targeting Uplift (Strong Evidence):** Targeted accounts achieved a **12.74% recovery rate** vs untargeted accounts at **12.97%** ($p = 0.42$). Current targeting expends 80%+ of call center capacity on borrowers who pay voluntarily.

### 3. Is the Reported 11% Improvement Real?
- **No, it is 100% false.**
- **Actual change:** Normalized daily run rate grew by only **+0.25%** from February to March.
- The entire 10.99% reported MoM surge was an artifact of March having 3 more calendar days than February (31 / 28 = +10.71%).

### 4. Where Should We Invest ₹10 Cr?
- **RECOMMENDATION: Invest ₹10.00 Cr in Option 4 — "Better Borrower Targeting (Propensity & Uplift ML Engine)".**
- **Strategic Rationale:** Untargeted accounts recover at 12.97% while targeted accounts recover at 12.74%. The business wastes 80%+ of its capacity contacting borrowers who would pay anyway. Targeting is the force multiplier that makes existing channels productive.
- **Financial Return Model:**
  - **Base Case Uplift:** +3.00% incremental recovery on the ₹10,500 Cr portfolio.
  - **Expected Incremental Recovery:** **₹31.50 Cr**
  - **Total Investment Cost:** ₹10.00 Cr
  - **Net Financial Profit:** **₹21.50 Cr**
  - **Expected Net ROI:** **+215.0%**
  - **Break-Even Payback Period:** **3.8 Months**
  - **Downside Scenario (+1.0% Min Lift):** ₹10.50 Cr recovery, fully recouping capital with a 5.0% net gain (11.4-month payback).
  - **Confidence Interval (90%):** ₹21.0 Cr to ₹36.75 Cr incremental recovery.

---

## Deliverables Directory Structure

```
credsolve assignment/
├── README.md                           <- Master project summary & guide (this file)
├── raw_data/                           <- Original 17 CSV files + data_dictionary + README
├── golden_data/                        <- Certified Dimensional Model & Parquet Data
│   ├── credsolve_golden.duckdb         <- Portable standalone DuckDB analytical warehouse
│   ├── golden_accounts.parquet / .csv
│   ├── golden_borrowers.parquet / .csv
│   ├── golden_agents.parquet / .csv
│   ├── golden_payments.parquet / .csv
│   ├── golden_calls.parquet / .csv
│   ├── golden_dispositions.parquet / .csv
│   ├── golden_interactions.parquet / .csv
│   ├── golden_payment_attribution.parquet / .csv
│   └── golden_monthly_metrics.parquet / .csv
├── sql/                                <- Production SQL Repository
│   ├── 01_raw_ddl.sql                  <- Staging layer DDL
│   ├── 02_data_cleaning.sql            <- Deduplication, SCD resolution, timestamp hygiene
│   ├── 03_transformations.sql         <- Omnichannel unified events & attribution engine
│   ├── 04_metric_definitions.sql       <- Standardized KPIs challenging flawed legacy metrics
│   └── 05_analytical_forensics.sql     <- Forensic audit queries (Forensics A through G)
├── pipeline/
│   ├── build_golden_dataset.py         <- Automated end-to-end Python/DuckDB ETL pipeline
│   └── generate_notebook.py            <- Generates analytical charts & Jupyter notebook
├── notebooks/
│   ├── collections_investigation.ipynb <- Reproducible Jupyter notebook with all analyses
│   ├── notebook_export.html            <- Standalone HTML export of the notebook
│   └── figures/                        <- High-resolution publication charts (Fig 1 - Fig 6)
│       ├── fig1_monthly_daily_recovery.png
│       ├── fig2_attribution_decay.png
│       ├── fig3_inactive_telephony_vendors.png
│       ├── fig4_simpsons_paradox_dpd.png
│       ├── fig5_targeted_vs_untargeted.png
│       └── fig6_investment_roi_comparison.png
├── reports/
│   ├── executive_memo.md               <- 2-Page Executive Memo answering the 5 CEO questions
│   ├── executive_memo.html             <- Clean print-ready HTML executive memo
│   ├── data_quality_report.md          <- Formal Data Quality Report (Raw -> Clean -> Golden)
│   └── architecture_design.md          <- Production Data Architecture Specification
├── architecture/
│   ├── production_architecture.svg     <- High-res visual production architecture diagram
│   └── architecture_spec.md            <- Engineering architecture companion guide
└── dashboard/
    ├── index.html                      <- Standalone 60-Second CEO Executive Cockpit
    └── executive_dashboard.html        <- Dashboard direct copy
```

---

## How to Run & Reproduce Everything

### 1. Rebuild the Golden Dataset
Run the automated ETL pipeline to recreate the DuckDB database and export all Parquet/CSV files:
```bash
python3 pipeline/build_golden_dataset.py
```

### 2. Run the Analytical Visualizations & Notebook Generator
Generate all 6 publication charts and compile the Jupyter notebook:
```bash
python3 pipeline/generate_notebook.py
```

### 3. Open the Interactive Executive Dashboard
Open `dashboard/index.html` in any web browser. It is completely self-contained with no external CDN dependencies:
```bash
open dashboard/index.html
```

### 4. Query the Certified Golden Database in SQL
Query `credsolve_golden.duckdb` directly using DuckDB CLI or Python:
```python
import duckdb
con = duckdb.connect("golden_data/credsolve_golden.duckdb")
print(con.execute("SELECT * FROM golden_monthly_metrics").fetchdf())
```

### 5. Inspect the Executive Memo
Open `reports/executive_memo.html` or read `reports/executive_memo.md`.
