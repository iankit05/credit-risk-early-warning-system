-- ============================================================
-- 04_feature_engineering.sql
-- Credit Risk Early Warning System
-- Author: Ankit Shrivas
-- Description: Feature engineering — combines all 5 analytics
-- tables into one master customer risk feature table
-- 6 risk features calculated per customer:
-- 1. Debt-to-Income Ratio (DTI)
-- 2. Loan Burden Score
-- 3. Previous Default Count
-- 4. Missed Payment Ratio
-- 5. Employment Stability
-- 6. Credit Utilization
-- ============================================================

USE WAREHOUSE fintech_wh;
USE DATABASE credit_risk_db;
USE SCHEMA analytics;

-- ============================================================
-- MASTER FEATURE TABLE: customer_risk_features
-- Joins all 5 dim/fact tables into one row per customer
-- 307,511 rows — one per customer
-- LEFT JOIN used throughout to preserve thin-file customers
-- ============================================================
CREATE OR REPLACE TABLE analytics.customer_risk_features AS
SELECT
    -- Customer identity & demographics
    c.CUSTOMER_ID,
    c.GENDER,
    c.AGE,
    c.AGE_BAND,
    c.EDUCATION,
    c.FAMILY_STATUS,
    c.HOUSING_TYPE,
    c.OCCUPATION,
    c.EMPLOYER_TYPE,
    c.INCOME_TYPE,
    c.ANNUAL_INCOME,
    c.INCOME_BAND,
    c.REGION_RATING,
    c.DEFAULT_FLAG,

    -- FEATURE 1: Debt-to-Income Ratio
    -- High DTI = heavy loan burden relative to income
    -- Dataset note: AMT_CREDIT = full loan lifetime value
    -- so DTI reflects total burden, not annual
    -- Threshold adjusted: >300% = high (not standard 50%)
    l.DTI_PCT,
    CASE
        WHEN l.DTI_PCT > 300 THEN 'High DTI'
        WHEN l.DTI_PCT BETWEEN 150 AND 300 THEN 'Medium DTI'
        ELSE 'Low DTI'
    END                                                     AS DTI_CATEGORY,

    -- FEATURE 2: Loan Burden Score
    -- Monthly repayment as multiple of monthly income
    -- >1.0 means repayment exceeds monthly income (unaffordable)
    l.LOAN_BURDEN_SCORE,
    l.LOAN_AMOUNT,
    l.ANNUAL_REPAYMENT,

    -- FEATURE 3: Previous Application History
    -- Refusal count is strongest signal — banks refused for a reason
    l.TOTAL_PREV_APPLICATIONS,
    l.PREV_APPROVED,
    l.PREV_REFUSED,
    l.PREV_CANCELED,

    -- FEATURE 4: Credit Bureau History & Previous Defaults
    -- COALESCE to 0 for thin-file customers (no bureau records)
    -- Conservative assumption: no history ≠ bad history
    COALESCE(ch.TOTAL_BUREAU_RECORDS, 0)                   AS TOTAL_BUREAU_RECORDS,
    COALESCE(ch.ACTIVE_CREDITS, 0)                         AS ACTIVE_CREDITS,
    COALESCE(ch.CLOSED_CREDITS, 0)                         AS CLOSED_CREDITS,
    COALESCE(ch.TOTAL_DEBT, 0)                             AS TOTAL_DEBT,
    COALESCE(ch.TOTAL_OVERDUE, 0)                          AS TOTAL_OVERDUE,
    COALESCE(ch.MAX_OVERDUE, 0)                            AS MAX_OVERDUE,
    COALESCE(ch.TOTAL_DAYS_OVERDUE, 0)                     AS TOTAL_DAYS_OVERDUE,
    COALESCE(ch.PREV_DEFAULT_COUNT, 0)                     AS PREV_DEFAULT_COUNT,

    -- FEATURE 5: Missed Payment Ratio & DPD
    -- Aggregated to customer level from fact_payment_history
    -- COALESCE to 0/100: no payment history = assume perfect
    COALESCE(ph.MISSED_PAYMENT_RATIO, 0)                   AS MISSED_PAYMENT_RATIO,
    COALESCE(ph.AVG_DAYS_LATE, 0)                          AS AVG_DAYS_LATE,
    COALESCE(ph.MAX_DAYS_LATE, 0)                          AS MAX_DAYS_LATE,
    COALESCE(ph.MAX_DPD, 0)                                AS MAX_DPD,
    COALESCE(ph.DELINQUENT_MONTHS, 0)                      AS DELINQUENT_MONTHS,
    COALESCE(ph.PAYMENT_RATIO_PCT, 100)                    AS PAYMENT_RATIO_PCT,

    -- FEATURE 6: Credit Utilization
    -- Monthly utilization averaged across all credit card months
    -- Industry healthy threshold: <30%
    -- >80% = maxing out credit = strong default signal
    COALESCE(lp.AVG_CREDIT_UTILIZATION_PCT, 0)            AS AVG_CREDIT_UTILIZATION_PCT,
    COALESCE(lp.BELOW_MIN_PAYMENT_COUNT, 0)               AS BELOW_MIN_PAYMENT_COUNT,
    COALESCE(lp.MAX_CC_DPD, 0)                            AS MAX_CC_DPD,
    COALESCE(lp.AVG_CC_BALANCE, 0)                        AS AVG_CC_BALANCE,

    -- FEATURE 5 (continued): Employment Stability
    -- From dim_customer — years employed
    -- NULL = unemployed (captured from 365,243 fix in cleaning)
    c.YEARS_EMPLOYED,
    c.EMPLOYMENT_BAND

FROM analytics.dim_customer c
-- Loan features (always exists — same source as dim_customer)
LEFT JOIN analytics.dim_loan l
    ON c.CUSTOMER_ID = l.CUSTOMER_ID
-- Bureau history (1,700 customers have no bureau records)
LEFT JOIN analytics.dim_credit_history ch
    ON c.CUSTOMER_ID = ch.CUSTOMER_ID
-- Payment history aggregated to customer level
-- fact_payment_history is at customer-loan level
-- so we aggregate again here to get one row per customer
LEFT JOIN (
    SELECT
        CUSTOMER_ID,
        ROUND(AVG(MISSED_PAYMENT_RATIO), 4)                AS MISSED_PAYMENT_RATIO,
        ROUND(AVG(AVG_DAYS_LATE), 2)                       AS AVG_DAYS_LATE,
        MAX(MAX_DAYS_LATE)                                 AS MAX_DAYS_LATE,
        MAX(MAX_DPD)                                       AS MAX_DPD,
        SUM(DELINQUENT_MONTHS)                             AS DELINQUENT_MONTHS,
        ROUND(AVG(PAYMENT_RATIO_PCT), 4)                   AS PAYMENT_RATIO_PCT
    FROM analytics.fact_payment_history
    GROUP BY CUSTOMER_ID
) ph ON c.CUSTOMER_ID = ph.CUSTOMER_ID
-- Credit card performance
LEFT JOIN analytics.fact_loan_performance lp
    ON c.CUSTOMER_ID = lp.CUSTOMER_ID;

-- ============================================================
-- Verification: all 6 features populated correctly
-- ============================================================
SELECT COUNT(*) AS total_risk_features FROM analytics.customer_risk_features;
-- Expected: 307,511

-- Feature averages sanity check
SELECT
    ROUND(AVG(DTI_PCT), 2)                                  AS avg_dti,
    ROUND(AVG(LOAN_BURDEN_SCORE), 4)                        AS avg_burden,
    ROUND(AVG(PREV_DEFAULT_COUNT), 4)                       AS avg_prev_defaults,
    ROUND(AVG(MISSED_PAYMENT_RATIO), 4)                     AS avg_missed_pmt,
    ROUND(AVG(AVG_CREDIT_UTILIZATION_PCT), 2)               AS avg_utilization,
    ROUND(AVG(YEARS_EMPLOYED), 2)                           AS avg_years_employed
FROM analytics.customer_risk_features;
-- Expected results:
-- avg_dti:           ~395.76
-- avg_burden:        ~2.17
-- avg_prev_defaults: ~0.012
-- avg_missed_pmt:    ~6.54
-- avg_utilization:   ~9.15
-- avg_years_employed:~6.53

-- ============================================================
-- Business insight queries on feature data
-- ============================================================

-- Default rate by DTI category
SELECT
    DTI_CATEGORY,
    COUNT(*)                                                AS customers,
    ROUND(AVG(DEFAULT_FLAG) * 100, 2)                      AS default_rate_pct
FROM analytics.customer_risk_features
GROUP BY DTI_CATEGORY
ORDER BY default_rate_pct DESC;

-- Default rate by employment band
SELECT
    EMPLOYMENT_BAND,
    COUNT(*)                                                AS customers,
    ROUND(AVG(DEFAULT_FLAG) * 100, 2)                      AS default_rate_pct
FROM analytics.customer_risk_features
GROUP BY EMPLOYMENT_BAND
ORDER BY default_rate_pct DESC;

-- Previous default impact on current default
SELECT
    CASE WHEN PREV_DEFAULT_COUNT = 0 THEN 'No Previous Defaults'
         WHEN PREV_DEFAULT_COUNT = 1 THEN '1 Previous Default'
         WHEN PREV_DEFAULT_COUNT = 2 THEN '2 Previous Defaults'
         ELSE '3+ Previous Defaults'
    END                                                     AS default_history,
    COUNT(*)                                                AS customers,
    ROUND(AVG(DEFAULT_FLAG) * 100, 2)                      AS default_rate_pct
FROM analytics.customer_risk_features
GROUP BY default_history
ORDER BY default_rate_pct DESC;
