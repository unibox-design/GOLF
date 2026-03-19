ARG RUNPOD_BASE_IMAGE=runpod/pytorch:1.0.2-cu1281-torch280-ubuntu2404
FROM ${RUNPOD_BASE_IMAGE}

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /opt/golf

COPY . /opt/golf

RUN apt-get update && \
    apt-get install -y --no-install-recommends git && \
    rm -rf /var/lib/apt/lists/*

CMD ["sleep", "infinity"]
