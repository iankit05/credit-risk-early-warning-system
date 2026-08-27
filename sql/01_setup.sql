-- ============================================================
-- 01_setup.sql
-- Credit Risk Early Warning System
-- Author: Ankit Shrivas
-- Description: Snowflake environment setup
-- Warehouse, Database, and Schema creation
-- ============================================================

-- Step 1: Create virtual warehouse (cost-optimized)
CREATE WAREHOUSE fintech_wh
  WAREHOUSE_SIZE = 'XSMALL'
  AUTO_SUSPEND = 60        -- Pauses after 60 seconds of inactivity
  AUTO_RESUME = TRUE       -- Wakes up automatically when query runs
  INITIALLY_SUSPENDED = TRUE;  -- Don't start until first query

-- Step 2: Create project database
CREATE DATABASE credit_risk_db;

-- Step 3: Create three schema layers (Medallion Architecture)
-- raw_data: untouched source data (never modified)
CREATE SCHEMA credit_risk_db.raw_data;

-- cleaned_data: validated, deduplicated, standardized
CREATE SCHEMA credit_risk_db.cleaned_data;

-- analytics: dimensional model for reporting and scoring
CREATE SCHEMA credit_risk_db.analytics;

-- Step 4: Set active context
USE WAREHOUSE fintech_wh;
USE DATABASE credit_risk_db;
USE SCHEMA raw_data;

-- ============================================================
-- Step 5: Create raw tables to receive CSV data
-- Load via Snowflake UI wizard (small files)
-- or gzip + UI wizard (files >250MB)
-- ============================================================

-- Table 1: Main customer application data (307,511 rows)
CREATE OR REPLACE TABLE raw_data.application_train (
    SK_ID_CURR              INTEGER,
    TARGET                  INTEGER,
    NAME_CONTRACT_TYPE      STRING,
    CODE_GENDER             STRING,
    FLAG_OWN_CAR            STRING,
    FLAG_OWN_REALTY         STRING,
    CNT_CHILDREN            INTEGER,
    AMT_INCOME_TOTAL        FLOAT,
    AMT_CREDIT              FLOAT,
    AMT_ANNUITY             FLOAT,
    AMT_GOODS_PRICE         FLOAT,
    NAME_TYPE_SUITE         STRING,
    NAME_INCOME_TYPE        STRING,
    NAME_EDUCATION_TYPE     STRING,
    NAME_FAMILY_STATUS      STRING,
    NAME_HOUSING_TYPE       STRING,
    DAYS_BIRTH              INTEGER,
    DAYS_EMPLOYED           INTEGER,
    OCCUPATION_TYPE         STRING,
    CNT_FAM_MEMBERS         FLOAT,
    REGION_RATING_CLIENT    INTEGER,
    ORGANIZATION_TYPE       STRING
);

-- Table 2: Credit bureau history (1,716,428 rows)
CREATE OR REPLACE TABLE raw_data.bureau (
    SK_ID_BUREAU            INTEGER,
    SK_ID_CURR              INTEGER,
    CREDIT_ACTIVE           STRING,
    CREDIT_CURRENCY         STRING,
    DAYS_CREDIT             INTEGER,
    CREDIT_DAY_OVERDUE      INTEGER,
    DAYS_CREDIT_ENDDATE     FLOAT,
    DAYS_ENDDATE_FACT       FLOAT,
    AMT_CREDIT_MAX_OVERDUE  FLOAT,
    CNT_CREDIT_PROLONG      INTEGER,
    AMT_CREDIT_SUM          FLOAT,
    AMT_CREDIT_SUM_DEBT     FLOAT,
    AMT_CREDIT_SUM_LIMIT    FLOAT,
    AMT_CREDIT_SUM_OVERDUE  FLOAT,
    CREDIT_TYPE             STRING,
    DAYS_CREDIT_UPDATE      INTEGER,
    AMT_ANNUITY             FLOAT
);

-- Table 3: Previous loan applications (1,670,214 rows)
CREATE OR REPLACE TABLE raw_data.previous_application (
    SK_ID_PREV              INTEGER,
    SK_ID_CURR              INTEGER,
    NAME_CONTRACT_TYPE      STRING,
    AMT_ANNUITY             FLOAT,
    AMT_APPLICATION         FLOAT,
    AMT_CREDIT              FLOAT,
    AMT_DOWN_PAYMENT        FLOAT,
    AMT_GOODS_PRICE         FLOAT,
    NAME_CONTRACT_STATUS    STRING,
    DAYS_DECISION           INTEGER,
    NAME_PAYMENT_TYPE       STRING,
    CODE_REJECT_REASON      STRING,
    NAME_CLIENT_TYPE        STRING,
    NAME_PRODUCT_TYPE       STRING,
    DAYS_FIRST_DUE          FLOAT,
    DAYS_LAST_DUE           FLOAT,
    CNT_PAYMENT             FLOAT
);

-- Table 4: Installment payment history (13,605,401 rows)
-- Loaded as gzip: 382MB compressed to 241MB
CREATE OR REPLACE TABLE raw_data.installments_payments (
    SK_ID_PREV              INTEGER,
    SK_ID_CURR              INTEGER,
    NUM_INSTALMENT_VERSION  FLOAT,
    NUM_INSTALMENT_NUMBER   INTEGER,
    DAYS_INSTALMENT         FLOAT,
    DAYS_ENTRY_PAYMENT      FLOAT,
    AMT_INSTALMENT          FLOAT,
    AMT_PAYMENT             FLOAT
);

-- Table 5: POS cash balance (10,001,358 rows)
-- Loaded as gzip: 374MB compressed
CREATE OR REPLACE TABLE raw_data.pos_cash_balance (
    SK_ID_PREV              INTEGER,
    SK_ID_CURR              INTEGER,
    MONTHS_BALANCE          INTEGER,
    CNT_INSTALMENT          FLOAT,
    CNT_INSTALMENT_FUTURE   FLOAT,
    NAME_CONTRACT_STATUS    STRING,
    SK_DPD                  INTEGER,
    SK_DPD_DEF              INTEGER
);

-- Table 6: Credit card balance (3,840,312 rows)
-- Loaded as gzip: 404MB compressed
CREATE OR REPLACE TABLE raw_data.credit_card_balance (
    SK_ID_PREV                      INTEGER,
    SK_ID_CURR                      INTEGER,
    MONTHS_BALANCE                  INTEGER,
    AMT_BALANCE                     FLOAT,
    AMT_CREDIT_LIMIT_ACTUAL         FLOAT,
    AMT_DRAWINGS_ATM_CURRENT        FLOAT,
    AMT_DRAWINGS_CURRENT            FLOAT,
    AMT_DRAWINGS_OTHER_CURRENT      FLOAT,
    AMT_DRAWINGS_POS_CURRENT        FLOAT,
    AMT_INST_MIN_REGULAR            FLOAT,
    AMT_PAYMENT_CURRENT             FLOAT,
    AMT_PAYMENT_TOTAL_CURRENT       FLOAT,
    AMT_RECEIVABLE_PRINCIPAL        FLOAT,
    AMT_RECIVABLE                   FLOAT,
    AMT_TOTAL_RECEIVABLE            FLOAT,
    CNT_DRAWINGS_ATM_CURRENT        FLOAT,
    CNT_DRAWINGS_CURRENT            INTEGER,
    CNT_DRAWINGS_OTHER_CURRENT      FLOAT,
    CNT_DRAWINGS_POS_CURRENT        FLOAT,
    CNT_INSTALMENT_MATURE_CUM       FLOAT,
    SK_DPD                          INTEGER,
    SK_DPD_DEF                      INTEGER
);

-- ============================================================
-- Verification queries (run after loading each file)
-- ============================================================
SELECT 'application_train'   AS table_name, COUNT(*) AS row_count FROM raw_data.application_train
UNION ALL
SELECT 'bureau',                             COUNT(*) FROM raw_data.bureau
UNION ALL
SELECT 'previous_application',               COUNT(*) FROM raw_data.previous_application
UNION ALL
SELECT 'installments_payments',              COUNT(*) FROM raw_data.installments_payments
UNION ALL
SELECT 'pos_cash_balance',                   COUNT(*) FROM raw_data.pos_cash_balance
UNION ALL
SELECT 'credit_card_balance',                COUNT(*) FROM raw_data.credit_card_balance;

-- Expected row counts:
-- application_train:    307,511
-- bureau:             1,716,428
-- previous_application: 1,670,214
-- installments_payments: 13,605,401
-- pos_cash_balance:   10,001,358
-- credit_card_balance:  3,840,312
-- TOTAL:             ~30,140,314
