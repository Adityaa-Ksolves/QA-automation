FROM jenkins/inbound-agent:lts-jdk17

USER root

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
  && rm -rf /var/lib/apt/lists/*

ENV CHROME_BIN=/usr/bin/chromium \
    BROWSER=chrome \
    WORKSPACE_ARTIFACT_DIR=artifacts

USER jenkins
