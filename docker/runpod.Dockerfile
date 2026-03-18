ARG RUNPOD_BASE_IMAGE=python:3.12-slim
FROM ${RUNPOD_BASE_IMAGE}

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /workspace/golf

COPY . /workspace/golf

RUN python3 -m pip install --upgrade pip && \
    pip install -r /workspace/golf/parameter-golf/requirements.txt

ENTRYPOINT ["bash", "-lc"]
CMD ["sleep infinity"]
