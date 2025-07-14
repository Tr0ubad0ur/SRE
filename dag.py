from datetime import datetime
from airflow import DAG
from airflow.operators.python import PythonOperator
import psycopg2

def write_to_db():
    conn = psycopg2.connect(
        host="host.mdb.yandexcloud.net", # тут id хоста
        port=6432,
        database="airflow",
        user="airflow_user",
        password="airflow42",
        sslmode="require"
    )
    cursor = conn.cursor()
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS test_table (
            id SERIAL PRIMARY KEY,
            message TEXT,
            created_at TIMESTAMP
        )
    """)
    cursor.execute(
        "INSERT INTO test_table (message, created_at) VALUES (%s, %s)",
        ("Hello from Airflow", datetime.now())
    )
    conn.commit()
    cursor.close()
    conn.close()

with DAG(
    dag_id='db_dag',
    start_date=datetime(2025, 7, 12),
    schedule_interval=None,
    catchup=False
) as dag:
    task = PythonOperator(
        task_id='write_to_db',
        python_callable=write_to_db
    )