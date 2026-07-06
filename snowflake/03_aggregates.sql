-- ============================================================
-- 03_aggregates.sql
-- Analytical views on top of LOGS_CLEAN for the dashboard /
-- ad-hoc queries. These read from LOGS_CLEAN, not the stream,
-- so they can be queried anytime without consuming it.
-- ============================================================

USE DATABASE LOG_PIPELINE_DB;
USE SCHEMA ANALYTICS;

-- Traffic per minute -------------------------------------------------------
CREATE OR REPLACE VIEW TRAFFIC_PER_MINUTE AS
SELECT
  DATE_TRUNC('MINUTE', event_timestamp) AS minute,
  COUNT(*)                              AS request_count,
  AVG(response_time_ms)                 AS avg_response_time_ms
FROM LOGS_CLEAN
GROUP BY 1
ORDER BY 1 DESC;

-- Error rate per minute ------------------------------------------------
CREATE OR REPLACE VIEW ERROR_RATE_PER_MINUTE AS
SELECT
  DATE_TRUNC('MINUTE', event_timestamp)               AS minute,
  COUNT(*)                                             AS total_requests,
  SUM(IFF(status_code >= 400, 1, 0))                   AS error_count,
  ROUND(100.0 * SUM(IFF(status_code >= 400, 1, 0))
        / NULLIF(COUNT(*), 0), 2)                      AS error_rate_pct
FROM LOGS_CLEAN
GROUP BY 1
ORDER BY 1 DESC;

-- Top endpoints (last hour) ------------------------------------------------
CREATE OR REPLACE VIEW TOP_ENDPOINTS_LAST_HOUR AS
SELECT
  endpoint,
  COUNT(*)               AS request_count,
  AVG(response_time_ms)  AS avg_response_time_ms
FROM LOGS_CLEAN
WHERE event_timestamp >= DATEADD(HOUR, -1, CURRENT_TIMESTAMP())
GROUP BY endpoint
ORDER BY request_count DESC
LIMIT 20;

-- p95 response time per endpoint (last hour) -------------------------------
CREATE OR REPLACE VIEW P95_RESPONSE_TIME_LAST_HOUR AS
SELECT
  endpoint,
  APPROX_PERCENTILE(response_time_ms, 0.95) AS p95_response_time_ms,
  COUNT(*)                                  AS request_count
FROM LOGS_CLEAN
WHERE event_timestamp >= DATEADD(HOUR, -1, CURRENT_TIMESTAMP())
GROUP BY endpoint
ORDER BY p95_response_time_ms DESC;

-- Quick smoke-test queries ---------------------------------------------
-- SELECT * FROM TRAFFIC_PER_MINUTE LIMIT 20;
-- SELECT * FROM ERROR_RATE_PER_MINUTE LIMIT 20;
-- SELECT * FROM TOP_ENDPOINTS_LAST_HOUR;
