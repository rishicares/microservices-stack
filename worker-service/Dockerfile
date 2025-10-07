# syntax=docker/dockerfile:1.7

FROM python:3.12-slim AS base
ENV PYTHONDONTWRITEBYTECODE=1 \
	PYTHONUNBUFFERED=1
WORKDIR /app

RUN groupadd -r app && useradd -r -g app app

FROM base AS deps
RUN apt-get update && apt-get install -y --no-install-recommends build-essential wget && rm -rf /var/lib/apt/lists/*
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

FROM base AS runtime
USER app
COPY --from=deps /usr/local /usr/local
COPY --chown=app:app app ./app
ENV WORKER_INTERVAL_SECONDS=5
EXPOSE 8080
HEALTHCHECK --interval=10s --timeout=3s --retries=5 CMD wget -qO- http://127.0.0.1:8080/health >/dev/null 2>&1 || exit 1
CMD ["python","-m","app.worker"]
