-- ============================================================
-- 05_risk_scoring_engine.sql
-- Credit Risk Early Warning System
-- Author: Ankit Shrivas
-- Description: Rule-based Early Warning System
-- Assigns risk points per customer across 8 rules
-- Classifies every customer into Low/Medium/High Risk
-- Calculates high risk loan exposure
-- ============================================================

USE WAREHOUSE fintech_wh;
USE DATABASE credit_risk_db;
USE SCHEMA analytics;

-- ============================================================
-- RISK SCORING TABLE: customer_risk_scores
-- Source: analytics.customer_risk_features
-- Output: 307,511 customers with risk score and category
--
-- SCORING LOGIC:
-- Rule 1: DTI > 300%              → +30 points
-- Rule 2: DTI 150-300%            → +15 points
-- Rule 3: Previous default        → +25 points
-- Rule 4: Employment < 2 years    → +20 points
-- Rule 5: Credit utilization >80% → +15 points
-- Rule 6: Credit utilization 50-80%→ +8 points
-- Rule 7: Missed payments >20%    → +10 points
-- Rule 8: Missed payments 10-20%  → +5 points
-- Rule 9: Previous refusals 2+    → +10 points
-- Rule 10: Previous refusals 1    → +5 points
-- Rule 11: Max DPD > 90 days      → +10 points
-- Rule 12: Max DPD 30-90 days     → +5 points
-- Rule 13: Delinquent months > 5  → +5 points
--
-- RISK CATEGORIES:
-- Low Risk:    0-30 points
-- Medium Risk: 31-60 points
-- High Risk:   61-100 points
-- ============================================================
CREATE OR REPLACE TABLE analytics.customer_risk_scores AS
SELECT
    -- Customer identity & demographics
    CUSTOMER_ID,
    GENDER,
    AGE,
    AGE_BAND,
    EDUCATION,
    FAMILY_STATUS,
    HOUSING_TYPE,
    OCCUPATION,
    INCOME_TYPE,
    ANNUAL_INCOME,
    INCOME_BAND,
    YEARS_EMPLOYED,
    EMPLOYMENT_BAND,
    REGION_RATING,
    DEFAULT_FLAG,
    LOAN_AMOUNT,

    -- Risk features (for dashboard reference)
    DTI_PCT,
    DTI_CATEGORY,
    LOAN_BURDEN_SCORE,
    PREV_DEFAULT_COUNT,
    MISSED_PAYMENT_RATIO,
    AVG_CREDIT_UTILIZATION_PCT,
    AVG_DAYS_LATE,
    MAX_DPD,
    DELINQUENT_MONTHS,
    PREV_REFUSED,
    TOTAL_PREV_APPLICATIONS,
    PAYMENT_RATIO_PCT,
    TOTAL_DEBT,
    TOTAL_OVERDUE,

    -- ============================================================
    -- RISK SCORE CALCULATION
    -- Sum of all rule points = final risk score (0-100+)
    -- ============================================================
    (
        -- Rule 1-2: Debt-to-Income Ratio
        -- DTI adjusted for dataset: full loan value vs annual income
        -- Standard 50% threshold not applicable here
        CASE
            WHEN DTI_PCT > 300 THEN 30
            WHEN DTI_PCT BETWEEN 150 AND 300 THEN 15
            ELSE 0
        END

        -- Rule 3: Previous defaults from bureau
        -- Past behavior = strongest predictor of future behavior
        + CASE WHEN PREV_DEFAULT_COUNT >= 1 THEN 25 ELSE 0 END

        -- Rule 4: Employment stability
        -- < 2 years or unemployed = income instability risk
        + CASE
            WHEN YEARS_EMPLOYED IS NULL THEN 20
            WHEN YEARS_EMPLOYED < 2 THEN 20
            ELSE 0
        END

        -- Rule 5-6: Credit utilization
        -- Industry healthy threshold: <30%
        -- >80% = maxing out available credit = financial stress
        + CASE
            WHEN AVG_CREDIT_UTILIZATION_PCT > 80 THEN 15
            WHEN AVG_CREDIT_UTILIZATION_PCT BETWEEN 50 AND 80 THEN 8
            ELSE 0
        END

        -- Rule 7-8: Missed payment ratio
        -- Consistent lateness signals inability to service debt
        + CASE
            WHEN MISSED_PAYMENT_RATIO > 20 THEN 10
            WHEN MISSED_PAYMENT_RATIO BETWEEN 10 AND 20 THEN 5
            ELSE 0
        END

        -- Rule 9-10: Previous loan refusals
        -- Banks refused for a reason — prior red flags identified
        + CASE
            WHEN PREV_REFUSED >= 2 THEN 10
            WHEN PREV_REFUSED = 1 THEN 5
            ELSE 0
        END

        -- Rule 11-12: Maximum DPD (Days Past Due)
        -- RBI NPA threshold: 90+ DPD
        -- Using SK_DPD_DEF (excludes minor processing delays)
        + CASE
            WHEN MAX_DPD > 90 THEN 10
            WHEN MAX_DPD BETWEEN 30 AND 90 THEN 5
            ELSE 0
        END

        -- Rule 13: Persistent delinquency pattern
        -- >5 delinquent months = recurring financial distress
        + CASE WHEN DELINQUENT_MONTHS > 5 THEN 5 ELSE 0 END

    )                                                       AS RISK_SCORE,

    -- ============================================================
    -- RISK CATEGORY CLASSIFICATION
    -- Low:    0-30  points
    -- Medium: 31-60 points
    -- High:   61+   points
    -- ============================================================
    CASE
        WHEN (
            CASE WHEN DTI_PCT > 300 THEN 30
                 WHEN DTI_PCT BETWEEN 150 AND 300 THEN 15
                 ELSE 0 END
            + CASE WHEN PREV_DEFAULT_COUNT >= 1 THEN 25 ELSE 0 END
            + CASE WHEN YEARS_EMPLOYED IS NULL THEN 20
                   WHEN YEARS_EMPLOYED < 2 THEN 20
                   ELSE 0 END
            + CASE WHEN AVG_CREDIT_UTILIZATION_PCT > 80 THEN 15
                   WHEN AVG_CREDIT_UTILIZATION_PCT BETWEEN 50 AND 80 THEN 8
                   ELSE 0 END
            + CASE WHEN MISSED_PAYMENT_RATIO > 20 THEN 10
                   WHEN MISSED_PAYMENT_RATIO BETWEEN 10 AND 20 THEN 5
                   ELSE 0 END
            + CASE WHEN PREV_REFUSED >= 2 THEN 10
                   WHEN PREV_REFUSED = 1 THEN 5
                   ELSE 0 END
            + CASE WHEN MAX_DPD > 90 THEN 10
                   WHEN MAX_DPD BETWEEN 30 AND 90 THEN 5
                   ELSE 0 END
            + CASE WHEN DELINQUENT_MONTHS > 5 THEN 5 ELSE 0 END
        ) >= 61 THEN 'High Risk'
        WHEN (
            CASE WHEN DTI_PCT > 300 THEN 30
                 WHEN DTI_PCT BETWEEN 150 AND 300 THEN 15
                 ELSE 0 END
            + CASE WHEN PREV_DEFAULT_COUNT >= 1 THEN 25 ELSE 0 END
            + CASE WHEN YEARS_EMPLOYED IS NULL THEN 20
                   WHEN YEARS_EMPLOYED < 2 THEN 20
                   ELSE 0 END
            + CASE WHEN AVG_CREDIT_UTILIZATION_PCT > 80 THEN 15
                   WHEN AVG_CREDIT_UTILIZATION_PCT BETWEEN 50 AND 80 THEN 8
                   ELSE 0 END
            + CASE WHEN MISSED_PAYMENT_RATIO > 20 THEN 10
                   WHEN MISSED_PAYMENT_RATIO BETWEEN 10 AND 20 THEN 5
                   ELSE 0 END
            + CASE WHEN PREV_REFUSED >= 2 THEN 10
                   WHEN PREV_REFUSED = 1 THEN 5
                   ELSE 0 END
            + CASE WHEN MAX_DPD > 90 THEN 10
                   WHEN MAX_DPD BETWEEN 30 AND 90 THEN 5
                   ELSE 0 END
            + CASE WHEN DELINQUENT_MONTHS > 5 THEN 5 ELSE 0 END
        ) >= 31 THEN 'Medium Risk'
        ELSE 'Low Risk'
    END                                                     AS RISK_CATEGORY,

    -- ============================================================
    -- HIGH RISK EXPOSURE
    -- Loan amount at risk for High Risk customers only
    -- Medium and Low Risk = 0 (intentional design)
    -- Used to quantify financial exposure in High Risk segment
    -- ============================================================
    CASE
        WHEN (
            CASE WHEN DTI_PCT > 300 THEN 30
                 WHEN DTI_PCT BETWEEN 150 AND 300 THEN 15
                 ELSE 0 END
            + CASE WHEN PREV_DEFAULT_COUNT >= 1 THEN 25 ELSE 0 END
            + CASE WHEN YEARS_EMPLOYED IS NULL THEN 20
                   WHEN YEARS_EMPLOYED < 2 THEN 20
                   ELSE 0 END
            + CASE WHEN AVG_CREDIT_UTILIZATION_PCT > 80 THEN 15
                   WHEN AVG_CREDIT_UTILIZATION_PCT BETWEEN 50 AND 80 THEN 8
                   ELSE 0 END
            + CASE WHEN MISSED_PAYMENT_RATIO > 20 THEN 10
                   WHEN MISSED_PAYMENT_RATIO BETWEEN 10 AND 20 THEN 5
                   ELSE 0 END
            + CASE WHEN PREV_REFUSED >= 2 THEN 10
                   WHEN PREV_REFUSED = 1 THEN 5
                   ELSE 0 END
            + CASE WHEN MAX_DPD > 90 THEN 10
                   WHEN MAX_DPD BETWEEN 30 AND 90 THEN 5
                   ELSE 0 END
            + CASE WHEN DELINQUENT_MONTHS > 5 THEN 5 ELSE 0 END
        ) >= 61 THEN LOAN_AMOUNT
        ELSE 0
    END                                                     AS HIGH_RISK_EXPOSURE

FROM analytics.customer_risk_features;

-- ============================================================
-- FINAL VERIFICATION — The headline result of this project
-- ============================================================

-- Total scored customers
SELECT COUNT(*) AS total_scored FROM analytics.customer_risk_scores;
-- Expected: 307,511

-- Risk distribution — the money shot
SELECT
    RISK_CATEGORY,
    COUNT(*)                                                AS customers,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2)      AS pct_of_portfolio,
    ROUND(SUM(LOAN_AMOUNT) / 1000000, 2)                   AS exposure_millions,
    ROUND(AVG(RISK_SCORE), 2)                              AS avg_risk_score,
    SUM(DEFAULT_FLAG)                                       AS actual_defaults_caught,
    ROUND(SUM(DEFAULT_FLAG) * 100.0
        / NULLIF(COUNT(*), 0), 2)                          AS default_rate_in_segment
FROM analytics.customer_risk_scores
GROUP BY RISK_CATEGORY
ORDER BY
    CASE RISK_CATEGORY
        WHEN 'High Risk' THEN 1
        WHEN 'Medium Risk' THEN 2
        ELSE 3
    END;

-- Expected results:
-- High Risk:   12,354 customers | 4.02% | ₹8,706M  | 14.09% default rate
-- Medium Risk: 152,054 customers| 49.45%| ₹99,723M | 9.01% default rate
-- Low Risk:    143,103 customers| 46.54%| ₹75,777M | 6.56% default rate

-- ============================================================
-- BUSINESS INSIGHT QUERIES
-- ============================================================

-- Portfolio default rate (overall)
SELECT
    ROUND(AVG(DEFAULT_FLAG) * 100, 2)                      AS portfolio_default_rate_pct
FROM analytics.customer_risk_scores;
-- Expected: 8.07%

-- Risk concentration paradox
-- Medium Risk carries far more total exposure than High Risk
-- despite lower individual default probability
SELECT
    RISK_CATEGORY,
    COUNT(*)                                                AS customers,
    ROUND(SUM(LOAN_AMOUNT) / 1000000, 2)                   AS total_exposure_millions,
    ROUND(AVG(DEFAULT_FLAG) * 100, 2)                      AS default_rate_pct,
    ROUND(SUM(LOAN_AMOUNT) / 1000000 *
        AVG(DEFAULT_FLAG), 2)                              AS expected_loss_millions
FROM analytics.customer_risk_scores
GROUP BY RISK_CATEGORY
ORDER BY total_exposure_millions DESC;

-- Age band risk analysis
SELECT
    AGE_BAND,
    COUNT(*)                                                AS customers,
    ROUND(AVG(DEFAULT_FLAG) * 100, 2)                      AS default_rate_pct,
    ROUND(AVG(RISK_SCORE), 2)                              AS avg_risk_score
FROM analytics.customer_risk_scores
GROUP BY AGE_BAND
ORDER BY default_rate_pct DESC;
-- Under 25 should show highest default rate (~12.31%)

-- Income band risk analysis
SELECT
    INCOME_BAND,
    COUNT(*)                                                AS customers,
    ROUND(AVG(DEFAULT_FLAG) * 100, 2)                      AS default_rate_pct
FROM analytics.customer_risk_scores
GROUP BY INCOME_BAND
ORDER BY default_rate_pct DESC;

-- Employment stability validation
-- Confirms +20 point rule for <2 years employment is data-backed
SELECT
    EMPLOYMENT_BAND,
    COUNT(*)                                                AS customers,
    ROUND(AVG(DEFAULT_FLAG) * 100, 2)                      AS default_rate_pct,
    ROUND(AVG(RISK_SCORE), 2)                              AS avg_risk_score
FROM analytics.customer_risk_scores
GROUP BY EMPLOYMENT_BAND
ORDER BY default_rate_pct DESC;

-- High risk customers sorted by risk score
-- These are the customers requiring immediate underwriting review
SELECT
    CUSTOMER_ID,
    RISK_SCORE,
    RISK_CATEGORY,
    LOAN_AMOUNT,
    DTI_PCT,
    PREV_DEFAULT_COUNT,
    MISSED_PAYMENT_RATIO,
    AVG_CREDIT_UTILIZATION_PCT,
    YEARS_EMPLOYED,
    DEFAULT_FLAG
FROM analytics.customer_risk_scores
WHERE RISK_CATEGORY = 'High Risk'
ORDER BY RISK_SCORE DESC
LIMIT 50;
