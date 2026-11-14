# The SQL job's image (docs/specs/round-1.md#the-sql-job), pushed to obs/sql-job in the stg shared registry.
FROM python:3.12-slim

RUN useradd --uid 10001 --no-create-home --shell /usr/sbin/nologin job
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir --disable-pip-version-check -r requirements.txt
COPY sql_job.py log_scan.py ./

USER 10001
ENV PYTHONUNBUFFERED=1 PGSSLMODE=require
ENTRYPOINT ["python3", "/app/sql_job.py"]
