# Jenkins VPN QA POC

This package implements a Jenkins-based POC for running QA sanity automation against customer environments that are reachable only from customer-specific VPN or private networks.

The model is:

1. Keep the Jenkins controller centralized.
2. Deploy one containerized Jenkins inbound agent on each customer/client server.
3. Label each agent by customer, for example `customer-piedmont`.
4. Run parameterized Jenkins jobs on the selected customer agent.
5. Perform connectivity checks before running the QA sanity script.
6. Archive logs, screenshots, reports, and test output from each run.

## Contents

- `Jenkinsfile` - parameterized pipeline for customer-routed sanity runs.
- `Jenkinsfile.daily` - daily fan-out pipeline that triggers one customer-scoped run per customer.
- `agent/Dockerfile` - reusable Jenkins inbound agent image with network test utilities and browser dependencies.
- `agent/requirements-qa-base.txt` - base Python packages installed into the agent image for Behave/Selenium automation.
- `agent/start-agent-nerdctl.sh` - builds and starts one Jenkins inbound agent using `nerdctl`.
- `agent/stop-agent-nerdctl.sh` - stops and removes the customer agent container.
- `agent/logs-agent-nerdctl.sh` - follows agent container logs.
- `agent/shell-agent-nerdctl.sh` - opens a shell in the running agent container.
- `agent/docker-compose.yml` - optional reference template only; the recommended path uses plain `nerdctl`.
- `agent/.env.example` - required environment variables for the agent container.
- `config/customers.yaml.example` - customer inventory and label convention.
- `scripts/connectivity-check.sh` - DNS, TCP/TLS, and HTTP reachability validation.
- `scripts/run-qa-sanity.sh` - wrapper for invoking the existing QA automation command.
- `scripts/tag-synthetic-monitoring-feature.py` - generates a customer-tagged copy of the multi-customer Behave feature.
- `scripts/validate-customer-tags.sh` - verifies the synthetic monitoring feature has required customer tags.
- `docs/customer-tagging.md` - how to split multi-customer Behave examples into customer-tagged blocks.
- `docs/runbook.md` - setup, onboarding, validation, and operations runbook.
- `docs/security-and-isolation.md` - security controls for multi-customer execution.

## Quick Start

On the Jenkins controller:

1. Create a Jenkins node for each customer using inbound agent mode.
2. Use node labels matching `customer-<customer-key>`, such as `customer-piedmont`.
3. Store customer application credentials in Jenkins Credentials.
4. Create a single-customer pipeline job using `Jenkinsfile` from this repository.
5. Create the optional daily fan-out job using `Jenkinsfile.daily`.

On each client/customer server:

1. Confirm `nerdctl` and containerd are available.
2. Copy `agent/.env.example` to `agent/.env` and fill in the Jenkins agent values.
3. Build and start the agent:

```bash
./agent/start-agent-nerdctl.sh
```

Follow logs:

```bash
./agent/logs-agent-nerdctl.sh
```

In Jenkins:

1. Run the pipeline.
2. Select `CUSTOMER`.
3. Provide the `ENVIRONMENT_URL`.
4. Provide `TEST_TAGS` with both tags, for example `@synthetic_monitoring and @customer_piedmont`.
5. Provide the real QA command in `QA_TEST_COMMAND`, or use the default Python/Behave command.

Example QA command:

```bash
python3 -m venv --system-site-packages .venv
. .venv/bin/activate
pip install --upgrade pip
if [ -f requirements.txt ]; then pip install -r requirements.txt; fi
behave features --tags "${TEST_TAGS}" -D browser="${BROWSER}" -D endpoint="${TARGET_URL}" --junit --junit-directory artifacts/test-results
```

## Recommended POC Acceptance Criteria

- The selected customer agent comes online from the client network.
- Connectivity check succeeds from that agent to the VPN-protected URL.
- The QA sanity script runs without QA engineer workstation VPN access.
- Jenkins archives logs and test artifacts.
- A job for one customer cannot accidentally run on another customer's agent.
