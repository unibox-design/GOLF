ARG TRAINER_BASE_IMAGE=python:3.12-slim
FROM ${TRAINER_BASE_IMAGE}

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /workspace

COPY parameter-golf/requirements.txt /tmp/parameter-golf-requirements.txt

RUN python -m pip install --upgrade pip && \
    pip install -r /tmp/parameter-golf-requirements.txt

ENTRYPOINT ["bash", "-lc"]
