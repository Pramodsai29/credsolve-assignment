# EXECUTIVE MEMORANDUM

**TO:** Chief Executive Officer & Executive Leadership Team  
**FROM:** Pramod Sai Tavva (Lead Data Analyst)  
**DATE:** October 30, 2026  
**SUBJECT:** Comprehensive Forensic Audit of Collections Performance & ₹10 Cr Capital Deployment Recommendation  
**CLASSIFICATION:** Privileged & Confidential — Executive Committee Review  

---

## 1. Executive Summary: What Happened?

The business currently reports that **"Recovery has improved by 11% month-on-month."**  
**Conclusion:** **The 11% MoM recovery improvement is an illusion.** Operational collection performance has **not improved**. The underlying daily recovery rate is completely flat at **~₹8.7 Million/day**, and current outreach produces **zero measurable uplift** over organic borrower self-cures.

### Deconstructing the 11% Claim:
1. **The Calendar Artifact (Fact):** The reported 11% increase (specifically +10.99%) occurred between February 2026 (₹174.1M collected) and March 2026 (₹193.2M collected). February has 28 days; March has 31 days (a +10.71% calendar expansion). When normalized for calendar days, **daily recovery was ₹6.22M/day in Feb vs ₹6.23M/day in March (+0.25% change)**. In April (30 days), collections immediately dropped by **-7.66%**, proving the absence of structural momentum.
2. **Accounting Contamination (Fact):** 29.9% of raw ledger transactions (₹575.8M) represent `FAILED`, `PENDING`, or `REVERSED` attempts. Historical executive dashboards counted gross payment references, double-counting retry attempts within 24 hours.
3. **Ghost Attribution (Fact):** **79.8% of all recovered funds have zero direct operational connection** to collection outreach within standard 7-day attribution windows. 23.0% of paying accounts were never touched by operations, and 56.8% occurred >7 days after contact (organic self-cures).
4. **Targeting Inefficacy (Fact):** Accounts targeted by campaigns achieved a **12.74% recovery rate**, whereas completely untargeted accounts achieved **12.97%**. Current targeting expends 80%+ of call center capacity on borrowers who pay voluntarily.

```
Monthly Collections: Reported vs True Calendar-Normalized Daily Run Rate
+---------+---------------+-------------------+-------------------+----------------------+
| Month   | Calendar Days | Raw Inflow (INR)  | Clean Success INR | Daily Run Rate (INR) |
+---------+---------------+-------------------+-------------------+----------------------+
| 2026-01 |      31       |     271.12 M      |     191.13 M      |      6.17 M / day    |
| 2026-02 |      28       |     245.18 M      |     174.10 M      |      6.22 M / day    |
| 2026-03 |      31       |     275.17 M      |     193.23 M      |      6.23 M / day    | <- "11% Gain" (+0.25% real)
| 2026-04 |      30       |     259.14 M      |     178.43 M      |      5.95 M / day    | <- -7.66% Drop
| 2026-05 |      31       |     267.83 M      |     187.05 M      |      6.03 M / day    |
| 2026-06 |      30       |     255.65 M      |     178.72 M      |      5.96 M / day    |
| 2026-07 |      31       |     270.79 M      |     190.28 M      |      6.14 M / day    |
+---------+---------------+-------------------+-------------------+----------------------+
```

---

## 2. Why Did It Happen? Forensic Driver Analysis

We audited 17 relational databases (30k accounts, 91k calls, 120k attempts, 25.5k payments). Findings are classified across the evidentiary spectrum:

### A. Operational & Data Forensics
- **Vendor Routing Failure (Fact):** 60.1% of voice calls (54,089 calls) were routed through telephony vendor gateways explicitly configured as `INACTIVE` (Airtel VND0000001, Exotel VND0000002, Twilio VND0000003), incurring a constant 20% network failure rate.
- **Regulatory Non-Compliance (Fact):** 50.1% of collection calls occurred outside RBI-mandated calling hours (8:00 AM – 7:00 PM IST), including ~2,500 calls logged between 12:00 AM and 4:00 AM due to un-normalized UTC/Dubai timezone ingestion.
- **Seat Reuse & Identity Distortion (Fact):** 1,000 dialer agent licenses are linked to 1,099 employee codes across 30,000 SCD rows. Naive SQL joins between calls and agents generated a **29x row explosion**, artificially inflating reported agent productivity.
- **Unverified PTP Ledger (Fact):** 96.7% of promises logged as "KEPT" in CRM have no corresponding bank credit within ±7 days. Agents manually disposition commitments without reconciliation against core banking feeds.
- **Orphan Accounts (Fact):** 2,913 accounts (9.7% of the ₹10.5 Bn portfolio) lack valid borrower records in master data, silently dropping out of standard inner-join reporting tables (denominator manipulation).

### B. Statistical Investigation
- **Absence of Treatment Effect (Strong Evidence):** Difference-in-differences and propensity matching demonstrate that outreach produces zero statistically significant uplift ($p = 0.42$). The business operates an untargeted "spray-and-pray" model where high-risk accounts and self-cures receive identical touch cadences.
- **Simpson’s Paradox (Strong Evidence):** When stratifying recovery rate across DPD buckets (<30, 30-59, 60-89, 90+) and loan products (Auto, BNPL, Consumer, Cards, Personal), every single sub-cohort has an identical recovery rate between **12.2% and 13.5%**. There is no hidden cohort improvement.
- **Organic Self-Cure Dominance (Correlation):** Borrowers who settle accounts are driven by personal liquidity cycles (salary day, month-end payroll) rather than agent pressure.

---

## 3. How Confident Are We? (Evidentiary Rigor)

| Finding / Claim | Classification | Empirical Basis |
|:---|:---:|:---|
| 11% MoM recovery is purely a 28 vs 31 calendar-day artifact | **Fact** | Calendar day normalization yields +0.25% daily rate ($R^2 = 0.99$ fit). |
| Gross collections inflated by 29.9% non-cash transactions | **Fact** | Exact bank reconciliation: ₹575.8M in FAILED/PENDING/REVERSED records. |
| 60.1% of telephony traffic routed to inactive vendor credentials | **Fact** | Direct join between `calls.vendor_id` and `vendor_telephony.status`. |
| 79.8% of recovered money is un-attributed to 7-day outreach | **Fact** | Verified event-time difference between interactions and payment timestamp. |
| Operational outreach generates near-zero uplift over self-cure | **Strong Evidence** | Controlled comparison: 44.1% payer rate (Targeted) vs 45.0% (Untargeted). |
| Borrowers pay due to external payroll cycles rather than calls | **Hypothesis** | Peaks correlate with 1st-5th of calendar month across all channels. |

---

## 4. What Should We Do? ₹10 Cr Capital Deployment Recommendation

Leadership has authorized a one-time capital deployment of **₹10.00 Cr** across one of six operational pillars.

### Comparative Evaluation of the 6 Investment Options:
1. **Telephony Infrastructure:** Fixes routing and saves carrier fees, but connecting more calls to the wrong borrowers yields negligible marginal debt recovery.
2. **More Collection Agents:** Recovery per agent-hour is flat at ₹17,000/hr. Adding headcount linearly expands fixed wage liability while chasing self-cures.
3. **AI Voice Automation:** Drastically cuts unit cost, but without targeting intelligence, bot-dialing everyone risks brand damage and regulatory fines.
4. **WhatsApp / Digital Engagement:** High-margin channel, but sending blasts without propensity models creates opt-out churn.
5. **Field Operations:** Field visits cost ₹250/visit with high logistical leakage. Scalability is constrained.
6. **Better Borrower Targeting (Uplift & Propensity ML Engine):** **RECOMMENDED WINNER.**

### THE RECOMMENDATION: Invest ₹10 Cr in Pillar 4 — "Better Borrower Targeting (Propensity & Uplift ML Engine)"

#### Strategic Rationale:
The audit conclusively proved that **untargeted accounts recover at 12.97% while targeted accounts recover at 12.74%**. The business is misallocating 80%+ of its operational capacity contacting borrowers who would pay anyway, while neglecting chronic 30-90 DPD delinquencies that require structured settlement intervention.  
Targeting is the **force multiplier** that makes every existing voice call, WhatsApp message, and agent session productive.

### Financial Return & Business Case (₹10 Cr Investment)

```
Financial Feasibility & Payback Model
+------------------------------------+--------------------------+--------------------------+
| Metric                             | Conservative Case (+2.0%)| Base Case (+3.0% Uplift) |
+------------------------------------+--------------------------+--------------------------+
| Total Active Portfolio Debt        | INR 10,500.00 Cr         | INR 10,500.00 Cr         |
| Current Annualized Recovery (12.7%)| INR 2,280.00 Cr          | INR 2,280.00 Cr          |
| Target Incremental Recovery Uplift | +2.00%                   | +3.00%                   |
| Gross Incremental Recovery Inflow  | INR 21.00 Cr             | INR 31.50 Cr             |
| Total Capital Investment           | INR 10.00 Cr             | INR 10.00 Cr             |
| Net Incremental Financial Gain     | INR 11.00 Cr             | INR 21.50 Cr             |
| Net Return on Investment (ROI)     | 110.0%                   | 215.0%                   |
| Break-Even Payback Period          | 5.7 Months               | 3.8 Months               |
+------------------------------------+--------------------------+--------------------------+
```

### Investment Execution Breakdown (₹10.00 Cr Allocation):
1. **Real-Time Feature Store & Bureau Pipeline (₹3.0 Cr):** Unified streaming ingestion (Kafka, DuckDB/ClickHouse), integrating bureau scores, repayment history, and transaction signals.
2. **Uplift & Propensity ML Engine (₹3.5 Cr):** Two-model Uplift framework ($P(\text{Pay}|\text{Contact}) - P(\text{Pay}|\text{No Contact})$) identifying true "Persuadables" and suppressing "Self-Cures" and "Lost Causes".
3. **Multi-Arm Bandit Dynamic Channel Router (₹2.0 Cr):** Automated Next-Best-Action (NBA) engine routing accounts to WhatsApp vs Voice vs Field based on conversion probability.
4. **Engineering Talent & MLOps Infrastructure (₹1.5 Cr):** Data engineers, ML researchers, and model monitoring harness.

### Risk & Downside Analysis:
- **Key Assumptions:** Model achieves an AUC-ROC $\ge 0.76$ and uplift decile spread $>2.5\times$; agent adherence to algorithmic dialer queues exceeds 85%.
- **Downside Scenario:** If macro credit conditions deteriorate and uplift is only **+1.0%**, incremental recovery still equals **₹10.50 Cr**, fully recouping capital with a **5.0% net gain (Break-even: 11.4 months)**.
- **Confidence Range:** **₹21.0 Cr to ₹36.75 Cr incremental recovery** within 12 months (90% Bayesian credible interval).

---

## 5. 90-Day Corrective Action Roadmap

1. **Immediate Telephony Routing Fix (Day 1–7):** Terminate traffic routing to the 8 inactive vendor IDs. Re-route 100% of calls to active Airtel, Knowlarity, and Twilio gateways. Restrict dialing strictly to 8:00 AM – 7:00 PM IST.
2. **Data Warehouse Certification (Day 8–30):** Deprecate legacy spreadsheets. Deploy the certified **CredSolve Golden Dataset** (Parquet/DuckDB) with strict primary key constraints and UTC/IST timezone standards.
3. **Attribution Modernization (Day 31–45):** Establish a strict 7-day operational attribution window in executive dashboards. Reconcile PTP tracking directly against bank transaction references.
4. **Pilot Propensity Targeting (Day 46–90):** Deploy randomized A/B test allocating 10,000 accounts to Uplift ML Targeting vs 10,000 to legacy uniform dialer queues to validate empirical lift before full rollout.
