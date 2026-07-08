# ── NZ Labour Market Intelligence — Ingestion Pipeline ──────────────────────
# One-off/scheduled job image, not a long-running service — run on demand or
# via an external scheduler with:
#   docker compose --profile ingestion run ingestion

FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        libffi-dev \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

ENTRYPOINT ["python", "run_pipeline.py"]
