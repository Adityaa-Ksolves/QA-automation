ARG JENKINS_AGENT_BASE_IMAGE=jenkins/inbound-agent:latest-jdk17
FROM ${JENKINS_AGENT_BASE_IMAGE}

USER root

COPY agent/requirements-qa-base.txt /tmp/requirements-qa-base.txt

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    ca-certificates \
    chromium \
    chromium-driver \
    curl \
    dnsutils \
    git \
    jq \
    netcat-openbsd \
    openssl \
    procps \
    python3 \
    python3-pip \
    python3-venv \
    unzip \
    wget \
    xvfb \
  && python3 -m venv /opt/qa-venv \
  && /opt/qa-venv/bin/pip install --upgrade pip \
  && /opt/qa-venv/bin/pip install -r /tmp/requirements-qa-base.txt \
  && rm -rf /var/lib/apt/lists/* /tmp/requirements-qa-base.txt

ENV CHROME_BIN=/usr/bin/chromium \
    BROWSER=chrome \
    PATH=/opt/qa-venv/bin:$PATH \
    QA_SECRET_DIR=/home/jenkins/qa-secrets \
    WORKSPACE_ARTIFACT_DIR=artifacts

USER jenkins
