# Credit Risk Early Warning System
### End-to-End BFSI Analytics Project | Snowflake · SQL · Tableau

---

## Project Overview

Banks and lending institutions face significant financial losses due to customer 
loan defaults. Traditional risk assessment methods identify problems only **after** 
delinquency occurs — too late to prevent losses.

This project builds a **Credit Risk Early Warning System (EWS)** that proactively 
identifies high-risk borrowers **before** default occurs by analyzing customer 
demographics, loan history, credit bureau data, repayment behavior, and portfolio 
metrics.

> Built to simulate a real-world banking analytics solution used by risk managers, credit officers, portfolio managers, and senior leadership teams.

---

## Live Dashboards

Dashboard -- Link
Executive Portfolio Health | [View Dashboard](https://public.tableau.com/views/CreditRiskEWS--ExecutivePortfolioHealth/Dashboard1-ExectivePortfolioHealth) |
Borrower Risk Analysis | [View Dashboard](https://public.tableau.com/views/CreditRiskEWS--BorrowerRiskAnalysis/Dashboard2-BorrowerRiskAnalysis) |
Early Warning System | [View Dashboard](https://public.tableau.com/views/CreditRiskEarlyWarningSystem--BFSIAnalyticsbyAnkitShrivas/Dashboard3-EarlyWarningSystem) 

---

## Key Findings

Metric -- Value 
| Total Customers Analyzed | 307,511 |
| Portfolio Default Rate | 8.07% |
| High Risk Customers Flagged | 12,354 (4% of portfolio) |
| High Risk Default Rate | 14.09% (vs 6.56% Low Risk) |
| High Risk Loan Exposure | ₹8,706M |
| Medium Risk Loan Exposure | ₹99,723M |
| Late Payment Rate | 8.43% across 13.6M installments |
| Avg Credit Utilization | 37.47% (above healthy 30% threshold) |

---

## Architecture

Raw Data (Kaggle CSVs)
↓
Snowflake Staging 
↓
raw_data schema (6 tables, 30M+ rows)
↓
cleaned_data schema (validated, deduplicated)
↓
analytics schema — Dimensional Model
├── dim_customer
├── dim_loan
├── dim_credit_history
├── fact_payment_history
└── fact_loan_performance
↓
customer_risk_features (6 engineered features)
↓
customer_risk_scores (rule-based EWS)
↓
Tableau Dashboards (3 interactive dashboards)


---

## Dataset

**Source:** [Home Credit Default Risk — Kaggle](https://www.kaggle.com/c/home-credit-default-risk)

File -- Rows -- Description 
| application_train.csv | 307,511 | Main customer application data |
| bureau.csv | 1,716,428 | Credit bureau history |
| previous_application.csv | 1,670,214 | Previous loan applications |
| installments_payments.csv | 13,605,401 | Repayment history |
| pos_cash_balance.csv | 10,001,358 | Consumer finance data |
| credit_card_balance.csv | 3,840,312 | Credit card behavior |
| **Total** | **~30M+** | **6 relational tables** |

---

## Tech Stack

Layer -- Tools 
| Cloud Data Warehouse | Snowflake (X-Small warehouse, auto-suspend) |
| Data Loading | SnowSQL |
| Snowflake SQL — window functions, CTEs, QUALIFY |
| Visualisation | Tableau Public (3 interactive dashboards) |
| Version Control | Git, GitHub |

---

## Risk Scoring Engine

Rule-based Early Warning Model assigning risk points per customer:

| Risk Factor | Condition | Points |
|---|---|---|
| Debt-to-Income | DTI > 300% | +30 |
| Previous Default | Any bureau default | +25 |
| Employment Stability | < 2 years employed | +20 |
| Credit Utilization | > 80% of limit used | +15 |
| Missed Payments | > 20% payments late | +10 |
| Previous Refusals | 2+ bank refusals | +10 |
| Max DPD | > 90 days past due | +10 |
| Delinquent Months | > 5 months delinquent | +5 |

**Risk Categories:**
- Low Risk: 0–30 points
- Medium Risk: 31–60 points  
- High Risk: 61–100 points

---

## Results

| Risk Category | Customers | % Portfolio | Default Rate | Loan Exposure |
|---|---|---|---|---|
| High Risk | 12,354 | 4.02% | 14.09% | ₹8,706M |
| Medium Risk | 152,054 | 49.45% | 9.01% | ₹99,723M |
| Low Risk | 143,103 | 46.54% | 6.56% | ₹75,777M |

**Key insight:** High Risk customers default at 14.09% — nearly double the 
portfolio average of 8.07% — validating the Early Warning System's 
discriminatory power.

---

## Business Recommendations

1. **Tighten underwriting for High Risk segment** — 12,354 customers flagged 
   with 14.09% default rate represent ₹8,706M in exposure. Recommend enhanced 
   credit review before approval.

2. **Proactive intervention for Medium Risk** — 152,054 customers carrying 
   ₹99,723M exposure (largest pool). Recommend payment reminders, restructuring 
   offers, and monthly monitoring.

3. **Fast-track Low Risk approvals** — 143,103 customers at 6.56% default rate 
   can be processed with streamlined workflows, reducing operational costs.

---

## Key Engineering Decisions

- **Medallion architecture** — raw → cleaned → analytics schema layering 
  (industry standard for data warehouses)
- **Handled 365,243 placeholder bug** — DAYS_EMPLOYED = 365,243 is a known 
  data quality issue indicating unemployed customers, nullified during cleaning
- **Gzip compression for large files** — three source files exceeded 
  Snowflake's 250MB UI upload limit. Compressed using gzip 
  (installments_payments: 382MB→241MB, pos_cash_balance: 374MB, 
  credit_card_balance: 404MB) and loaded as .csv.gz files via Snowflake's 
  Load Data wizard which natively handles gzip decompression during ingestion
- **Cost-optimized Snowflake setup** — X-Small warehouse with 60-second 
  auto-suspend to minimize credit consumption
- **LEFT JOIN throughout** — preserves 1,700 thin-file customers with no 
  bureau history rather than excluding them with INNER JOIN
- **QUALIFY for deduplication** — Snowflake-native syntax cleaner than 
  subquery-based deduplication

---

## SQL Scripts

All SQL scripts are organized in the `/sql` folder:

| Script | Description |
|---|---|
| 01_setup.sql | Warehouse, database, schema creation |
| 02_cleaning.sql | Data cleaning for all 6 tables |
| 03_data_mart.sql | Dimension and fact table creation |
| 04_feature_engineering.sql | 6 risk feature calculations |
| 05_risk_scoring_engine.sql | Rule-based scoring and classification |

---

## Author

**Ankit Shrivas**  
Data Analyst | SQL · Snowflake · Python · Tableau   
[Tableau Public](https://public.tableau.com/app/profile/ankit.shrivas) | 
[GitHub](https://github.com/iankit05)

--------------------------------xxx--------------------------------
