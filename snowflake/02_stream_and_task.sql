-- ============================================================
-- 02_stream_and_task.sql
-- Stream on RAW_LOGS captures new rows; a Task runs on a
-- schedule, flattens the VARIANT into typed columns, and
-- inserts into LOGS_CLEAN. This is the "incremental
-- processing" pattern SnowPro Core covers.
-- ============================================================

USE DATABASE LOG_PIPELINE_DB;
USE WAREHOUSE LOG_PIPELINE_WH;

-- 1. Stream on the raw table ---------------------------------------------
CREATE OR REPLACE STREAM RAW.RAW_LOGS_STREAM
  ON TABLE RAW.RAW_LOGS
  APPEND_ONLY = TRUE;   -- we only ever insert into RAW_LOGS, never update

-- 2. Clean/typed target table ---------------------------------------------
CREATE OR REPLACE TABLE ANALYTICS.LOGS_CLEAN (
  log_id           STRING,
  event_timestamp  TIMESTAMP_NTZ,
  ip_address       STRING,
  http_method      STRING,
  endpoint         STRING,
  status_code      NUMBER,
  response_time_ms NUMBER,
  user_agent       STRING,
  loaded_at        TIMESTAMP_NTZ
);

-- 3. Task: consume the stream on a schedule --------------------------------
CREATE OR REPLACE TASK ANALYTICS.LOAD_LOGS_CLEAN_TASK
  WAREHOUSE = LOG_PIPELINE_WH
  SCHEDULE = '1 MINUTE'
WHEN
  SYSTEM$STREAM_HAS_DATA('RAW.RAW_LOGS_STREAM')
AS
  INSERT INTO ANALYTICS.LOGS_CLEAN
  SELECT
    raw_record:log_id::STRING,
    raw_record:timestamp::TIMESTAMP_NTZ,
    raw_record:ip_address::STRING,
    raw_record:method::STRING,
    raw_record:endpoint::STRING,
    raw_record:status_code::NUMBER,
    raw_record:response_time_ms::NUMBER,
    raw_record:user_agent::STRING,
    loaded_at
  FROM RAW.RAW_LOGS_STREAM;

-- 4. Tasks are created suspended by default -- turn it on -----------------
ALTER TASK ANALYTICS.LOAD_LOGS_CLEAN_TASK RESUME;

-- 5. Useful checks ---------------------------------------------------------
-- SHOW TASKS IN SCHEMA ANALYTICS;
-- SELECT * FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY())
--   ORDER BY SCHEDULED_TIME DESC LIMIT 20;
-- SELECT COUNT(*) FROM ANALYTICS.LOGS_CLEAN;

-- To pause the task (e.g. to stop compute usage overnight):
-- ALTER TASK ANALYTICS.LOAD_LOGS_CLEAN_TASK SUSPEND;
