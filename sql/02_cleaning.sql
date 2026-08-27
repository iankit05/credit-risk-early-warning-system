-- ============================================================
-- 02_cleaning.sql
-- Credit Risk Early Warning System
-- Author: Ankit Shrivas
-- Description: Data cleaning for all 6 raw tables
-- Creates cleaned_data schema tables with:
-- - NULL handling
-- - Invalid value removal
-- - Deduplication (QUALIFY + ROW_NUMBER)
-- - Standardization (UPPER, TRIM)
-- - Derived columns (AGE_YEARS, YEARS_EMPLOYED)
-- ============================================================

USE WAREHOUSE fintech_wh;
USE DATABASE credit_risk_db;

-- ============================================================
-- TABLE 1: application_train
-- Key fixes:
-- 1. DAYS_BIRTH converted to AGE_YEARS (negative offset)
-- 2. DAYS_EMPLOYED = 365,243 is a placeholder for unemployed
-- 3. Negative income/credit amounts nullified
-- 4. Deduplication on SK_ID_CURR
-- ============================================================
CREATE OR REPLACE TABLE cleaned_data.application_train AS
SELECT
    SK_ID_CURR,
    TARGET,
    NAME_CONTRACT_TYPE,
    UPPER(TRIM(CODE_GENDER))                                AS CODE_GENDER,
    FLAG_OWN_CAR,
    FLAG_OWN_REALTY,
    CNT_CHILDREN,
    -- Negative/zero income is invalid
    CASE WHEN AMT_INCOME_TOTAL > 0
         THEN AMT_INCOME_TOTAL ELSE NULL END                AS AMT_INCOME_TOTAL,
    CASE WHEN AMT_CREDIT > 0
         THEN AMT_CREDIT ELSE NULL END                      AS AMT_CREDIT,
    AMT_ANNUITY,
    AMT_GOODS_PRICE,
    NAME_TYPE_SUITE,
    NAME_INCOME_TYPE,
    NAME_EDUCATION_TYPE,
    NAME_FAMILY_STATUS,
    NAME_HOUSING_TYPE,
    -- DAYS_BIRTH is negative (days before application date)
    -- Convert to positive age in years
    ABS(DAYS_BIRTH) / 365                                   AS AGE_YEARS,
    -- DAYS_EMPLOYED = 365,243 is a known placeholder for unemployed
    -- All others: convert negative days to positive years
    CASE WHEN DAYS_EMPLOYED = 365243 THEN NULL
         ELSE ABS(DAYS_EMPLOYED) / 365
    END                                                     AS YEARS_EMPLOYED,
    COALESCE(OCCUPATION_TYPE, 'Unknown')                    AS OCCUPATION_TYPE,
    CNT_FAM_MEMBERS,
    REGION_RATING_CLIENT,
    COALESCE(ORGANIZATION_TYPE, 'Unknown')                  AS ORGANIZATION_TYPE
FROM raw_data.application_train
WHERE SK_ID_CURR IS NOT NULL
-- Deduplication: keep one row per customer
-- QUALIFY is Snowflake-specific syntax for post-window filtering
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY SK_ID_CURR
    ORDER BY SK_ID_CURR
) = 1;

-- Verify
SELECT COUNT(*) AS cleaned_rows FROM cleaned_data.application_train;
-- Expected: ~307,511

-- ============================================================
-- TABLE 2: bureau
-- Key fixes:
-- 1. Negative credit amounts nullified
-- 2. COALESCE overdue amount to 0 (NULL = no overdue)
-- 3. Deduplication keeping most recently updated record
-- ============================================================
CREATE OR REPLACE TABLE cleaned_data.bureau AS
SELECT
    SK_ID_BUREAU,
    SK_ID_CURR,
    UPPER(TRIM(CREDIT_ACTIVE))                              AS CREDIT_ACTIVE,
    UPPER(TRIM(CREDIT_CURRENCY))                            AS CREDIT_CURRENCY,
    DAYS_CREDIT,
    CREDIT_DAY_OVERDUE,
    DAYS_CREDIT_ENDDATE,
    DAYS_ENDDATE_FACT,
    CASE WHEN AMT_CREDIT_MAX_OVERDUE < 0
         THEN NULL ELSE AMT_CREDIT_MAX_OVERDUE END          AS AMT_CREDIT_MAX_OVERDUE,
    CNT_CREDIT_PROLONG,
    CASE WHEN AMT_CREDIT_SUM < 0
         THEN NULL ELSE AMT_CREDIT_SUM END                  AS AMT_CREDIT_SUM,
    CASE WHEN AMT_CREDIT_SUM_DEBT < 0
         THEN NULL ELSE AMT_CREDIT_SUM_DEBT END             AS AMT_CREDIT_SUM_DEBT,
    CASE WHEN AMT_CREDIT_SUM_LIMIT < 0
         THEN NULL ELSE AMT_CREDIT_SUM_LIMIT END            AS AMT_CREDIT_SUM_LIMIT,
    -- NULL overdue = no overdue (replace with 0, not Unknown)
    COALESCE(AMT_CREDIT_SUM_OVERDUE, 0)                    AS AMT_CREDIT_SUM_OVERDUE,
    UPPER(TRIM(CREDIT_TYPE))                                AS CREDIT_TYPE,
    DAYS_CREDIT_UPDATE,
    COALESCE(AMT_ANNUITY, 0)                               AS AMT_ANNUITY
FROM raw_data.bureau
WHERE SK_ID_CURR IS NOT NULL
  AND SK_ID_BUREAU IS NOT NULL
-- Keep most recently updated bureau record per SK_ID_BUREAU
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY SK_ID_BUREAU
    ORDER BY DAYS_CREDIT_UPDATE DESC
) = 1;

-- Verify: check no negative amounts slipped through
SELECT
    MIN(AMT_CREDIT_SUM)         AS min_credit_sum,
    MIN(AMT_CREDIT_SUM_DEBT)    AS min_debt,
    MIN(AMT_CREDIT_MAX_OVERDUE) AS min_overdue
FROM cleaned_data.bureau;
-- All values should be 0, positive, or NULL

-- ============================================================
-- TABLE 3: previous_application
-- Key fixes:
-- 1. Negative financial amounts nullified
-- 2. NULL categorical fields replaced with 'Unknown'
-- 3. Deduplication keeping most recent decision
-- ============================================================
CREATE OR REPLACE TABLE cleaned_data.previous_application AS
SELECT
    SK_ID_PREV,
    SK_ID_CURR,
    UPPER(TRIM(NAME_CONTRACT_TYPE))                         AS NAME_CONTRACT_TYPE,
    CASE WHEN AMT_ANNUITY < 0
         THEN NULL ELSE AMT_ANNUITY END                     AS AMT_ANNUITY,
    CASE WHEN AMT_APPLICATION <= 0
         THEN NULL ELSE AMT_APPLICATION END                 AS AMT_APPLICATION,
    CASE WHEN AMT_CREDIT < 0
         THEN NULL ELSE AMT_CREDIT END                      AS AMT_CREDIT,
    CASE WHEN AMT_DOWN_PAYMENT < 0
         THEN NULL ELSE AMT_DOWN_PAYMENT END                AS AMT_DOWN_PAYMENT,
    CASE WHEN AMT_GOODS_PRICE <= 0
         THEN NULL ELSE AMT_GOODS_PRICE END                 AS AMT_GOODS_PRICE,
    UPPER(TRIM(NAME_CONTRACT_STATUS))                       AS NAME_CONTRACT_STATUS,
    DAYS_DECISION,
    COALESCE(NAME_PAYMENT_TYPE, 'Unknown')                  AS NAME_PAYMENT_TYPE,
    COALESCE(CODE_REJECT_REASON, 'Unknown')                 AS CODE_REJECT_REASON,
    COALESCE(NAME_CLIENT_TYPE, 'Unknown')                   AS NAME_CLIENT_TYPE,
    COALESCE(NAME_PRODUCT_TYPE, 'Unknown')                  AS NAME_PRODUCT_TYPE,
    DAYS_FIRST_DUE,
    DAYS_LAST_DUE,
    CASE WHEN CNT_PAYMENT < 0
         THEN NULL ELSE CNT_PAYMENT END                     AS CNT_PAYMENT
FROM raw_data.previous_application
WHERE SK_ID_CURR IS NOT NULL
  AND SK_ID_PREV IS NOT NULL
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY SK_ID_PREV
    ORDER BY DAYS_DECISION DESC
) = 1;

-- Contract status distribution (business insight)
SELECT
    NAME_CONTRACT_STATUS,
    COUNT(*)                                                AS count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2)      AS percentage
FROM cleaned_data.previous_application
GROUP BY NAME_CONTRACT_STATUS
ORDER BY count DESC;
-- Expected: APPROVED ~62%, CANCELED ~19%, REFUSED ~17%, UNUSED OFFER ~2%

-- ============================================================
-- TABLE 4: installments_payments
-- Key fixes:
-- 1. Negative payment amounts nullified
-- 2. Derived column: DAYS_LATE (positive = late, negative = early)
-- 3. Derived column: IS_LATE_PAYMENT (0/1 flag)
-- ============================================================
CREATE OR REPLACE TABLE cleaned_data.installments_payments AS
SELECT
    SK_ID_PREV,
    SK_ID_CURR,
    NUM_INSTALMENT_VERSION,
    NUM_INSTALMENT_NUMBER,
    DAYS_INSTALMENT,
    DAYS_ENTRY_PAYMENT,
    CASE WHEN AMT_INSTALMENT < 0
         THEN NULL ELSE AMT_INSTALMENT END                  AS AMT_INSTALMENT,
    CASE WHEN AMT_PAYMENT < 0
         THEN NULL ELSE AMT_PAYMENT END                     AS AMT_PAYMENT,
    -- How many days late was this payment?
    -- Positive = late, Negative = paid early, 0 = on time
    DAYS_ENTRY_PAYMENT - DAYS_INSTALMENT                    AS DAYS_LATE,
    -- Binary flag for easy aggregation later
    CASE WHEN DAYS_ENTRY_PAYMENT > DAYS_INSTALMENT
         THEN 1 ELSE 0 END                                  AS IS_LATE_PAYMENT
FROM raw_data.installments_payments
WHERE SK_ID_CURR IS NOT NULL
  AND SK_ID_PREV IS NOT NULL
  AND AMT_INSTALMENT IS NOT NULL;

-- Late payment rate (key business insight)
SELECT
    SUM(IS_LATE_PAYMENT)                                    AS late_payments,
    COUNT(*)                                                AS total_payments,
    ROUND(SUM(IS_LATE_PAYMENT) * 100.0 / COUNT(*), 2)      AS late_payment_pct
FROM cleaned_data.installments_payments;
-- Expected: ~8.43% late payment rate

-- ============================================================
-- TABLE 5: pos_cash_balance
-- Key fixes:
-- 1. Negative DPD values set to 0 (physically impossible)
-- 2. Negative instalment counts nullified
-- 3. Derived column: IS_DELINQUENT (0/1 flag)
-- ============================================================
CREATE OR REPLACE TABLE cleaned_data.pos_cash_balance AS
SELECT
    SK_ID_PREV,
    SK_ID_CURR,
    MONTHS_BALANCE,
    CASE WHEN CNT_INSTALMENT < 0
         THEN NULL ELSE CNT_INSTALMENT END                  AS CNT_INSTALMENT,
    CASE WHEN CNT_INSTALMENT_FUTURE < 0
         THEN NULL ELSE CNT_INSTALMENT_FUTURE END           AS CNT_INSTALMENT_FUTURE,
    UPPER(TRIM(NAME_CONTRACT_STATUS))                       AS NAME_CONTRACT_STATUS,
    -- DPD cannot be negative — set to 0
    CASE WHEN SK_DPD < 0
         THEN 0 ELSE SK_DPD END                             AS SK_DPD,
    CASE WHEN SK_DPD_DEF < 0
         THEN 0 ELSE SK_DPD_DEF END                         AS SK_DPD_DEF,
    -- Delinquency flag: was this month overdue?
    CASE WHEN SK_DPD > 0
         THEN 1 ELSE 0 END                                  AS IS_DELINQUENT
FROM raw_data.pos_cash_balance
WHERE SK_ID_CURR IS NOT NULL
  AND SK_ID_PREV IS NOT NULL;

-- Delinquency rate
SELECT
    SUM(IS_DELINQUENT)                                      AS delinquent_months,
    COUNT(*)                                                AS total_months,
    ROUND(SUM(IS_DELINQUENT) * 100.0 / COUNT(*), 2)        AS delinquency_rate_pct
FROM cleaned_data.pos_cash_balance;
-- Expected: ~2.95%

-- ============================================================
-- TABLE 6: credit_card_balance
-- Key fixes:
-- 1. Negative balances and amounts nullified
-- 2. Zero/negative credit limits nullified
-- 3. Derived: MONTHLY_CREDIT_UTILIZATION
-- 4. Derived: IS_BELOW_MIN_PAYMENT flag
-- ============================================================
CREATE OR REPLACE TABLE cleaned_data.credit_card_balance AS
SELECT
    SK_ID_PREV,
    SK_ID_CURR,
    MONTHS_BALANCE,
    CASE WHEN AMT_BALANCE < 0
         THEN NULL ELSE AMT_BALANCE END                     AS AMT_BALANCE,
    CASE WHEN AMT_CREDIT_LIMIT_ACTUAL <= 0
         THEN NULL ELSE AMT_CREDIT_LIMIT_ACTUAL END         AS AMT_CREDIT_LIMIT_ACTUAL,
    CASE WHEN AMT_DRAWINGS_CURRENT < 0
         THEN NULL ELSE AMT_DRAWINGS_CURRENT END            AS AMT_DRAWINGS_CURRENT,
    CASE WHEN AMT_PAYMENT_TOTAL_CURRENT < 0
         THEN NULL ELSE AMT_PAYMENT_TOTAL_CURRENT END       AS AMT_PAYMENT_TOTAL_CURRENT,
    CASE WHEN AMT_INST_MIN_REGULAR < 0
         THEN NULL ELSE AMT_INST_MIN_REGULAR END            AS AMT_INST_MIN_REGULAR,
    COALESCE(CNT_DRAWINGS_CURRENT, 0)                      AS CNT_DRAWINGS_CURRENT,
    CASE WHEN SK_DPD < 0 THEN 0 ELSE SK_DPD END            AS SK_DPD,
    CASE WHEN SK_DPD_DEF < 0 THEN 0 ELSE SK_DPD_DEF END    AS SK_DPD_DEF,
    -- Monthly credit utilization: balance as % of limit
    CASE WHEN AMT_CREDIT_LIMIT_ACTUAL > 0
         THEN ROUND(AMT_BALANCE / AMT_CREDIT_LIMIT_ACTUAL, 4)
         ELSE NULL
    END                                                     AS MONTHLY_CREDIT_UTILIZATION,
    -- Flag: paying less than minimum due (strong stress signal)
    CASE WHEN AMT_PAYMENT_TOTAL_CURRENT < AMT_INST_MIN_REGULAR
         AND AMT_INST_MIN_REGULAR > 0
         THEN 1 ELSE 0
    END                                                     AS IS_BELOW_MIN_PAYMENT
FROM raw_data.credit_card_balance
WHERE SK_ID_CURR IS NOT NULL
  AND SK_ID_PREV IS NOT NULL;

-- Credit card metrics
SELECT
    SUM(IS_BELOW_MIN_PAYMENT)                               AS below_min_count,
    COUNT(*)                                                AS total_records,
    ROUND(SUM(IS_BELOW_MIN_PAYMENT) * 100.0 / COUNT(*), 2) AS below_min_pct,
    ROUND(AVG(MONTHLY_CREDIT_UTILIZATION) * 100, 2)        AS avg_utilization_pct
FROM cleaned_data.credit_card_balance;
-- Expected: ~5.58% below minimum, ~37.47% avg utilization
