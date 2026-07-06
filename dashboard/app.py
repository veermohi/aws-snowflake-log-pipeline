"""
app.py - Simple Streamlit dashboard on top of the Snowflake aggregate views.

Requires:
    pip install streamlit snowflake-connector-python pandas

Run:
    streamlit run app.py

Set your Snowflake connection details as environment variables, or
replace the connect() call below with your preferred auth method
(key-pair auth is recommended over password for anything beyond a demo).
"""

import os

import pandas as pd
import snowflake.connector
import streamlit as st

st.set_page_config(page_title="Log Pipeline Dashboard", layout="wide")


@st.cache_resource
def get_connection():
    return snowflake.connector.connect(
        account=os.environ["SNOWFLAKE_ACCOUNT"],
        user=os.environ["SNOWFLAKE_USER"],
        password=os.environ.get("SNOWFLAKE_PASSWORD"),
        warehouse="LOG_PIPELINE_WH",
        database="LOG_PIPELINE_DB",
        schema="ANALYTICS",
    )


def run_query(sql: str) -> pd.DataFrame:
    conn = get_connection()
    cur = conn.cursor()
    try:
        cur.execute(sql)
        cols = [c[0] for c in cur.description]
        return pd.DataFrame(cur.fetchall(), columns=cols)
    finally:
        cur.close()


st.title("Real-Time Log Analytics")
st.caption("S3 -> Snowpipe -> Stream/Task -> Snowflake, refreshed every minute")

col1, col2 = st.columns(2)

with col1:
    st.subheader("Requests per minute")
    traffic_df = run_query("SELECT * FROM TRAFFIC_PER_MINUTE ORDER BY MINUTE ASC LIMIT 60")
    if not traffic_df.empty:
        st.line_chart(traffic_df.set_index("MINUTE")["REQUEST_COUNT"])
    else:
        st.info("No data yet - is the generator running?")

with col2:
    st.subheader("Error rate % per minute")
    error_df = run_query("SELECT * FROM ERROR_RATE_PER_MINUTE ORDER BY MINUTE ASC LIMIT 60")
    if not error_df.empty:
        st.line_chart(error_df.set_index("MINUTE")["ERROR_RATE_PCT"])
    else:
        st.info("No data yet.")

st.subheader("Top endpoints (last hour)")
top_df = run_query("SELECT * FROM TOP_ENDPOINTS_LAST_HOUR")
st.dataframe(top_df, use_container_width=True)

st.subheader("p95 response time by endpoint (last hour)")
p95_df = run_query("SELECT * FROM P95_RESPONSE_TIME_LAST_HOUR")
st.dataframe(p95_df, use_container_width=True)

st.caption("Refresh the page to pull the latest numbers.")
