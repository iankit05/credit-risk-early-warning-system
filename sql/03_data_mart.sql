-- ============================================================
-- 03_data_mart.sql
-- Credit Risk Early Warning System
-- Author: Ankit Shrivas
-- Description: Dimensional data mart creation
-- Follows star schema pattern:
-- - 3 dimension tables (WHO and WHAT)
-- - 2 fact tables (WHAT HAPPENED)
-- All tables built on cleaned_data schema
-- ============================================================

USE WAREHOUSE fintech_wh;
USE DATABASE credit_risk_db;
USE SCHEMA analytics;

-- ============================================================
-- DIMENSION TABLE 1: dim_customer
-- Source: cleaned_data.application_train
-- Purpose: Customer demographics and profile
-- One row per customer (307,511 rows)
-- ============================================================
CREATE OR REPLACE TABLE analytics.dim_customer AS
SELECT
    a.SK_ID_CURR                                            AS CUSTOMER_ID,
    a.CODE_GENDER                                           AS GENDER,
    a.AGE_YEARS                                             AS AGE,
    -- Age bands for dashboard grouping
    CASE
        WHEN a.AGE_YEARS < 25 THEN 'Under 25'
        WHEN a.AGE_YEARS BETWEEN 25 AND 34 THEN '25-34'
        WHEN a.AGE_YEARS BETWEEN 35 AND 44 THEN '35-44'
        WHEN a.AGE_YEARS BETWEEN 45 AND 54 THEN '45-54'
        ELSE '55+'
    END                                                     AS AGE_BAND,
    a.NAME_EDUCATION_TYPE                                   AS EDUCATION,
    a.NAME_FAMILY_STATUS                                    AS FAMILY_STATUS,
    a.NAME_HOUSING_TYPE                                     AS HOUSING_TYPE,
    a.CNT_CHILDREN                                          AS NUM_CHILDREN,
    a.CNT_FAM_MEMBERS                                       AS FAMILY_SIZE,
    a.OCCUPATION_TYPE                                       AS OCCUPATION,
    a.ORGANIZATION_TYPE                                     AS EMPLOYER_TYPE,
    a.YEARS_EMPLOYED                                        AS YEARS_EMPLOYED,
    -- Employment stability bands
    CASE
        WHEN a.YEARS_EMPLOYED IS NULL THEN 'Unemployed'
        WHEN a.YEARS_EMPLOYED < 2 THEN 'Under 2 Years'
        WHEN a.YEARS_EMPLOYED BETWEEN 2 AND 5 THEN '2-5 Years'
        WHEN a.YEARS_EMPLOYED BETWEEN 5 AND 10 THEN '5-10 Years'
        ELSE '10+ Years'
    END                                                     AS EMPLOYMENT_BAND,
    a.NAME_INCOME_TYPE                                      AS INCOME_TYPE,
    a.AMT_INCOME_TOTAL                                      AS ANNUAL_INCOME,
    -- Income bands for dashboard grouping
    CASE
        WHEN a.AMT_INCOME_TOTAL < 100000 THEN 'Low (<100K)'
        WHEN a.AMT_INCOME_TOTAL BETWEEN 100000 AND 200000 THEN 'Medium (100-200K)'
        WHEN a.AMT_INCOME_TOTAL BETWEEN 200000 AND 500000 THEN 'High (200-500K)'
        ELSE 'Very High (500K+)'
    END                                                     AS INCOME_BAND,
    a.REGION_RATING_CLIENT                                  AS REGION_RATING,
    a.TARGET                                                AS DEFAULT_FLAG
FROM cleaned_data.application_train a;

-- Verify
SELECT COUNT(*) AS total_customers FROM analytics.dim_customer;
-- Expected: 307,511

-- ============================================================
-- DIMENSION TABLE 2: dim_loan
-- Source: cleaned_data.application_train + previous_application
-- Purpose: Loan details, DTI ratio, previous application history
-- One row per customer (307,511 rows)
-- ============================================================
CREATE OR REPLACE TABLE analytics.dim_loan AS
SELECT
    a.SK_ID_CURR                                            AS CUSTOMER_ID,
    a.NAME_CONTRACT_TYPE                                    AS CONTRACT_TYPE,
    a.AMT_CREDIT                                            AS LOAN_AMOUNT,
    a.AMT_ANNUITY                                           AS ANNUAL_REPAYMENT,
    a.AMT_GOODS_PRICE                                       AS GOODS_PRICE,
    a.AMT_INCOME_TOTAL                                      AS ANNUAL_INCOME,
    -- FEATURE 1: Debt-to-Income Ratio
    -- Note: AMT_CREDIT = full loan lifetime value (not annual)
    -- DTI therefore reflects total loan burden vs annual income
    CASE
        WHEN a.AMT_INCOME_TOTAL > 0
        THEN ROUND(a.AMT_CREDIT / a.AMT_INCOME_TOTAL, 4)
        ELSE NULL
    END                                                     AS DEBT_TO_INCOME_RATIO,
    CASE
        WHEN a.AMT_INCOME_TOTAL > 0
        THEN ROUND(a.AMT_CREDIT / a.AMT_INCOME_TOTAL * 100, 4)
        ELSE NULL
    END                                                     AS DTI_PCT,
    -- FEATURE 2: Loan Burden Score
    -- Monthly repayment as fraction of monthly income
    CASE
        WHEN a.AMT_INCOME_TOTAL > 0
        THEN ROUND(a.AMT_ANNUITY / (a.AMT_INCOME_TOTAL / 12), 4)
        ELSE NULL
    END                                                     AS LOAN_BURDEN_SCORE,
    -- Previous application aggregates (LEFT JOIN preserves all customers)
    COUNT(p.SK_ID_PREV)                                     AS TOTAL_PREV_APPLICATIONS,
    SUM(CASE WHEN p.NAME_CONTRACT_STATUS = 'APPROVED'
        THEN 1 ELSE 0 END)                                  AS PREV_APPROVED,
    SUM(CASE WHEN p.NAME_CONTRACT_STATUS = 'REFUSED'
        THEN 1 ELSE 0 END)                                  AS PREV_REFUSED,
    SUM(CASE WHEN p.NAME_CONTRACT_STATUS = 'CANCELED'
        THEN 1 ELSE 0 END)                                  AS PREV_CANCELED
FROM cleaned_data.application_train a
LEFT JOIN cleaned_data.previous_application p
    ON a.SK_ID_CURR = p.SK_ID_CURR
GROUP BY
    a.SK_ID_CURR, a.NAME_CONTRACT_TYPE, a.AMT_CREDIT,
    a.AMT_ANNUITY, a.AMT_GOODS_PRICE, a.AMT_INCOME_TOTAL;

-- Verify
SELECT COUNT(*) AS total_loans FROM analytics.dim_loan;
-- Expected: 307,511

-- ============================================================
-- DIMENSION TABLE 3: dim_credit_history
-- Source: cleaned_data.bureau
-- Purpose: Bureau credit summary per customer
-- One row per customer (305,811 rows)
-- Note: 1,700 fewer than application_train =
-- thin-file customers with no bureau history
-- ============================================================
CREATE OR REPLACE TABLE analytics.dim_credit_history AS
SELECT
    b.SK_ID_CURR                                            AS CUSTOMER_ID,
    COUNT(b.SK_ID_BUREAU)                                   AS TOTAL_BUREAU_RECORDS,
    SUM(CASE WHEN b.CREDIT_ACTIVE = 'ACTIVE'
        THEN 1 ELSE 0 END)                                  AS ACTIVE_CREDITS,
    SUM(CASE WHEN b.CREDIT_ACTIVE = 'CLOSED'
        THEN 1 ELSE 0 END)                                  AS CLOSED_CREDITS,
    SUM(COALESCE(b.AMT_CREDIT_SUM, 0))                     AS TOTAL_CREDIT_SUM,
    SUM(COALESCE(b.AMT_CREDIT_SUM_DEBT, 0))                AS TOTAL_DEBT,
    SUM(COALESCE(b.AMT_CREDIT_SUM_OVERDUE, 0))             AS TOTAL_OVERDUE,
    MAX(COALESCE(b.AMT_CREDIT_MAX_OVERDUE, 0))             AS MAX_OVERDUE,
    SUM(COALESCE(b.CREDIT_DAY_OVERDUE, 0))                 AS TOTAL_DAYS_OVERDUE,
    -- FEATURE 3: Previous Default Count
    -- Proxy: bureau records where days overdue > 0
    SUM(CASE WHEN b.CREDIT_DAY_OVERDUE > 0
        THEN 1 ELSE 0 END)                                  AS PREV_DEFAULT_COUNT,
    COUNT(DISTINCT b.CREDIT_TYPE)                           AS DISTINCT_CREDIT_TYPES,
    MAX(b.DAYS_CREDIT_UPDATE)                               AS LAST_BUREAU_UPDATE
FROM cleaned_data.bureau b
GROUP BY b.SK_ID_CURR;

-- Verify
SELECT COUNT(*) AS total_credit_histories FROM analytics.dim_credit_history;
-- Expected: 305,811 (1,700 thin-file customers have no bureau records)

-- Sanity check
SELECT
    ROUND(AVG(TOTAL_BUREAU_RECORDS), 2)                     AS avg_bureau_records,
    ROUND(AVG(PREV_DEFAULT_COUNT), 2)                       AS avg_prev_defaults,
    MAX(PREV_DEFAULT_COUNT)                                 AS max_prev_defaults
FROM analytics.dim_credit_history;
-- Expected: avg ~5.61 records, max defaults = 7

-- ============================================================
-- FACT TABLE 1: fact_payment_history
-- Source: cleaned_data.installments_payments + pos_cash_balance
-- Purpose: Payment behavior per customer per previous loan
-- 997,752 rows (one per customer-loan combination)
-- ============================================================
CREATE OR REPLACE TABLE analytics.fact_payment_history AS
SELECT
    i.SK_ID_CURR                                            AS CUSTOMER_ID,
    i.SK_ID_PREV                                            AS PREV_LOAN_ID,
    COUNT(i.NUM_INSTALMENT_NUMBER)                          AS TOTAL_INSTALLMENTS,
    SUM(i.IS_LATE_PAYMENT)                                  AS LATE_PAYMENTS,
    -- FEATURE 4: Missed Payment Ratio
    ROUND(SUM(i.IS_LATE_PAYMENT) * 100.0
        / NULLIF(COUNT(*), 0), 4)                           AS MISSED_PAYMENT_RATIO,
    ROUND(AVG(CASE WHEN i.DAYS_LATE > 0
        THEN i.DAYS_LATE END), 2)                           AS AVG_DAYS_LATE,
    MAX(CASE WHEN i.DAYS_LATE > 0
        THEN i.DAYS_LATE END)                               AS MAX_DAYS_LATE,
    SUM(COALESCE(i.AMT_INSTALMENT, 0))                     AS TOTAL_SCHEDULED,
    SUM(COALESCE(i.AMT_PAYMENT, 0))                        AS TOTAL_PAID,
    ROUND(SUM(COALESCE(i.AMT_PAYMENT, 0)) * 100.0
        / NULLIF(SUM(COALESCE(i.AMT_INSTALMENT, 0)), 0), 4) AS PAYMENT_RATIO_PCT,
    -- DPD_DEF used instead of raw DPD
    -- DPD_DEF excludes minor delays within bank tolerance threshold
    MAX(COALESCE(p.SK_DPD_DEF, 0))                         AS MAX_DPD,
    SUM(COALESCE(p.IS_DELINQUENT, 0))                      AS DELINQUENT_MONTHS
FROM cleaned_data.installments_payments i
LEFT JOIN cleaned_data.pos_cash_balance p
    ON i.SK_ID_CURR = p.SK_ID_CURR
    AND i.SK_ID_PREV = p.SK_ID_PREV
GROUP BY i.SK_ID_CURR, i.SK_ID_PREV;

-- Verify
SELECT COUNT(*) AS total_payment_records FROM analytics.fact_payment_history;
-- Expected: 997,752

SELECT
    ROUND(AVG(MISSED_PAYMENT_RATIO), 2)                     AS avg_missed_pct,
    ROUND(AVG(PAYMENT_RATIO_PCT), 2)                        AS avg_payment_ratio,
    MAX(MAX_DPD)                                            AS worst_dpd_ever,
    ROUND(AVG(MAX_DAYS_LATE), 2)                            AS avg_max_days_late
FROM analytics.fact_payment_history;
-- Expected: ~6.91% missed, 98.71% payment ratio
-- Worst DPD: 2,907 days (nearly 8 years past due)

-- ============================================================
-- FACT TABLE 2: fact_loan_performance
-- Source: cleaned_data.application_train + credit_card_balance
-- Purpose: Default outcomes and credit card behavior
-- One row per customer (307,511 rows)
-- ============================================================
CREATE OR REPLACE TABLE analytics.fact_loan_performance AS
SELECT
    a.SK_ID_CURR                                            AS CUSTOMER_ID,
    a.TARGET                                                AS DEFAULT_FLAG,
    a.AMT_CREDIT                                            AS LOAN_AMOUNT,
    a.AMT_INCOME_TOTAL                                      AS ANNUAL_INCOME,
    a.AMT_ANNUITY                                           AS ANNUAL_REPAYMENT,
    -- FEATURE 5: Credit Utilization (averaged across all months)
    ROUND(AVG(cc.MONTHLY_CREDIT_UTILIZATION) * 100, 2)     AS AVG_CREDIT_UTILIZATION_PCT,
    SUM(COALESCE(cc.IS_BELOW_MIN_PAYMENT, 0))              AS BELOW_MIN_PAYMENT_COUNT,
    SUM(COALESCE(cc.AMT_DRAWINGS_CURRENT, 0))              AS TOTAL_CC_DRAWINGS,
    ROUND(AVG(COALESCE(cc.AMT_BALANCE, 0)), 2)             AS AVG_CC_BALANCE,
    MAX(COALESCE(cc.SK_DPD_DEF, 0))                        AS MAX_CC_DPD
FROM cleaned_data.application_train a
LEFT JOIN cleaned_data.credit_card_balance cc
    ON a.SK_ID_CURR = cc.SK_ID_CURR
GROUP BY
    a.SK_ID_CURR, a.TARGET, a.AMT_CREDIT,
    a.AMT_INCOME_TOTAL, a.AMT_ANNUITY;

-- Default rate verification (most important number in the project)
SELECT
    DEFAULT_FLAG,
    COUNT(*)                                                AS customers,
    ROUND(COUNT(*) * 100.0
        / SUM(COUNT(*)) OVER(), 2)                         AS pct
FROM analytics.fact_loan_performance
GROUP BY DEFAULT_FLAG;
-- Expected: 0 → 91.93% (282,686), 1 → 8.07% (24,825)
