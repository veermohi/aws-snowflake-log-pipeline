-- ============================================================
-- 01_stage_and_pipe.sql
-- Sets up: warehouse, database/schema, storage integration,
-- external stage, raw table, file format, and Snowpipe.
-- ============================================================

-- 1. Warehouse + database ------------------------------------------------
CREATE WAREHOUSE IF NOT EXISTS LOG_PIPELINE_WH
  WAREHOUSE_SIZE = 'XSMALL'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE;

CREATE DATABASE IF NOT EXISTS LOG_PIPELINE_DB;
CREATE SCHEMA IF NOT EXISTS LOG_PIPELINE_DB.RAW;
CREATE SCHEMA IF NOT EXISTS LOG_PIPELINE_DB.ANALYTICS;

USE WAREHOUSE LOG_PIPELINE_WH;
USE DATABASE LOG_PIPELINE_DB;
USE SCHEMA RAW;

-- 2. Storage integration ---------------------------------------------------
-- Run this once, then update the IAM role's trust policy with the
-- STORAGE_AWS_IAM_USER_ARN and STORAGE_AWS_EXTERNAL_ID that Snowflake
-- returns from DESC INTEGRATION (see comment below).
CREATE STORAGE INTEGRATION IF NOT EXISTS LOG_PIPELINE_S3_INT
  TYPE = EXTERNAL_STAGE
  STORAGE_PROVIDER = 'S3'
  ENABLED = TRUE
  STORAGE_AWS_ROLE_ARN = 'arn:aws:iam::<ACCOUNT_ID>:role/log-pipeline-snowflake-role'
  STORAGE_ALLOWED_LOCATIONS = ('s3://YOUR_BUCKET_NAME/raw/');

-- After creating, run this and copy the values into your AWS IAM role's
-- trust relationship (see infra/iam_policy.json for the S3-side policy):
-- DESC INTEGRATION LOG_PIPELINE_S3_INT;

-- 3. File format -------------------------------------------------------
CREATE OR REPLACE FILE FORMAT LOG_PIPELINE_DB.RAW.JSON_LINES_FORMAT
  TYPE = 'JSON'
  STRIP_OUTER_ARRAY = FALSE;

-- 4. External stage -----------------------------------------------------
CREATE OR REPLACE STAGE LOG_PIPELINE_DB.RAW.LOGS_STAGE
  URL = 's3://YOUR_BUCKET_NAME/raw/'
  STORAGE_INTEGRATION = LOG_PIPELINE_S3_INT
  FILE_FORMAT = LOG_PIPELINE_DB.RAW.JSON_LINES_FORMAT;

-- Sanity check: this should list files once the generator has uploaded some
-- LIST @LOG_PIPELINE_DB.RAW.LOGS_STAGE;

-- 5. Raw landing table ---------------------------------------------------
-- Land everything as a single VARIANT column; we'll flatten downstream.
-- This is a common, resilient pattern for semi-structured ingestion.
CREATE OR REPLACE TABLE LOG_PIPELINE_DB.RAW.RAW_LOGS (
  raw_record VARIANT,
  loaded_at  TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- 6. Snowpipe (auto-ingest) ----------------------------------------------
CREATE OR REPLACE PIPE LOG_PIPELINE_DB.RAW.LOGS_PIPE
  AUTO_INGEST = TRUE
AS
  COPY INTO LOG_PIPELINE_DB.RAW.RAW_LOGS (raw_record)
  FROM @LOG_PIPELINE_DB.RAW.LOGS_STAGE
  FILE_FORMAT = (FORMAT_NAME = LOG_PIPELINE_DB.RAW.JSON_LINES_FORMAT)
  MATCH_BY_COLUMN_NAME = NONE;

-- After creating, get the SQS ARN to wire up as the S3 bucket's event
-- notification target:
-- SHOW PIPES LIKE 'LOGS_PIPE';
-- (copy the notification_channel value into the S3 bucket's
--  Properties -> Event notifications -> send to this SQS queue)

-- 7. Check pipe status / troubleshoot -------------------------------------
-- SELECT SYSTEM$PIPE_STATUS('LOG_PIPELINE_DB.RAW.LOGS_PIPE');
-- SELECT * FROM TABLE(INFORMATION_SCHEMA.COPY_HISTORY(
--   TABLE_NAME => 'LOG_PIPELINE_DB.RAW.RAW_LOGS',
--   START_TIME => DATEADD(HOUR, -1, CURRENT_TIMESTAMP())));
