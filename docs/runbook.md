# Jenkins VPN QA POC Runbook

This runbook explains how to run existing Python/Behave QA sanity automation from a centralized Jenkins controller when customer application URLs are reachable only from customer-specific VPN or private networks.

The key idea is simple:

1. Jenkins controller stays centralized.
2. A Jenkins inbound agent container runs on a customer/client-side server.
3. That client server already has VPN/private access to the customer application.
4. Jenkins sends the job to the correct customer agent by node label.
5. The agent runs connectivity checks and then runs the existing Python/Behave test command.

The shell scripts in this POC do not replace the Python/Behave tests. They only prepare logs, run connectivity checks, and invoke the Behave command.

## 1. Architecture Overview

Recommended POC flow:

```text
QA user
  |
  | starts Jenkins job
  v
Jenkins controller
  |
  | schedules job using label customer-piedmont
  v
Jenkins inbound agent container on client server
  |
  | reaches customer URL through VPN/private network
  v
VPN-protected customer application
```

Example customer mapping:

| Customer | Jenkins Node | Jenkins Label | Application URL |
| --- | --- | --- | --- |
| Piedmont | `qa-agent-piedmont` | `customer-piedmont` | `https://piedmont.nimblethis.net/` |
| Zito | `qa-agent-zito` | `customer-zito` | `https://nimble-web.zitomedia.net/` |
| Comporium | `qa-agent-comporium` | `customer-comporium` | `https://comporiumv5.nimblethis.net/` |

For the POC, use one Jenkins agent container per customer.

## 2. Prerequisites

Before starting, confirm these items are available.

On the Jenkins controller:

- Jenkins is already installed and reachable from the client server.
- You have Jenkins admin access to create nodes and jobs.
- Jenkins can reach the source repository that contains this POC.
- Required plugins are installed:
  - Pipeline
  - JUnit
  - Credentials Binding
  - AnsiColor

On the client/customer server:

- containerd is installed and running.
- `nerdctl` is installed and connected to the containerd runtime.
- `nerdctl compose` is not required for this POC.
- The server can reach the customer application URL through VPN or private routing.
- The server can make outbound connections to the Jenkins controller.
- The server can pull or receive the QA automation code.

For Python/Behave tests:

- The QA repository contains Behave feature files and step definitions.
- A `requirements.txt` file exists, or the Python dependencies are known.
- The automation can run in headless browser mode.
- Test results can be generated in JUnit XML format.

## 3. Prepare Jenkins Controller

### 3.1 Install Jenkins Plugins

In Jenkins:

1. Go to `Manage Jenkins`.
2. Open `Plugins`.
3. Search for and install:
   - `Pipeline`
   - `JUnit`
   - `Credentials Binding`
   - `AnsiColor`
4. Restart Jenkins if Jenkins asks for it.

### 3.2 Create A Jenkins Node For One Customer

Create the first customer agent node. Example: Piedmont.

1. Go to `Manage Jenkins`.
2. Open `Nodes`.
3. Click `New Node`.
4. Enter node name:

```text
qa-agent-piedmont
```

5. Select `Permanent Agent`.
6. Click `Create`.
7. Configure the node:

```text
Name: qa-agent-piedmont
Description: QA sanity execution agent for Piedmont VPN/private environment
Number of executors: 1
Remote root directory: /home/jenkins/agent
Labels: customer-piedmont
Usage: Only build jobs with label expressions matching this node
Launch method: Launch agent by connecting it to the controller
Availability: Keep this agent online as much as possible
```

8. Save the node.
9. Open the node page again.
10. Copy the generated agent secret. It will be used in `agent/.env`.

Repeat this process for each customer. Use one node and one label per customer.

## 4. Prepare The Client Server

Run these steps on the server that has access to the customer application URL.

### 4.1 Confirm Network Access To Jenkins

Replace the URL with your Jenkins controller URL:

```bash
curl -I https://jenkins.example.com/
```

Expected result:

- HTTP response is returned.
- The command does not timeout.
- If Jenkins uses a private CA, the server must trust that CA or you must install it.

### 4.2 Confirm Network Access To The Customer Application

Example:

```bash
curl -Ik https://piedmont.nimblethis.net/
```

Expected result:

- DNS resolves.
- TCP connection succeeds.
- TLS handshake succeeds for HTTPS URLs.
- HTTP response is returned.

An HTTP `200`, `301`, `302`, `401`, or `403` is acceptable for the first connectivity check. The goal is to prove network reachability, not application login.

### 4.3 Copy Or Clone The POC Package

Place this POC package on the client server.

Example:

```bash
cd /opt
git clone <repo-url> jenkins-vpn-qa-poc
cd /opt/jenkins-vpn-qa-poc
```

If you are copying files manually, copy the whole `jenkins-vpn-qa-poc` directory.

## 5. Prepare The Jenkins Agent Container

### 5.1 Configure Agent Environment

From inside the POC directory:

```bash
cp agent/.env.example agent/.env
```

Edit `agent/.env`:

```bash
JENKINS_URL=https://jenkins.example.com/
JENKINS_AGENT_NAME=qa-agent-piedmont
JENKINS_SECRET=<secret from Jenkins node page>
CUSTOMER_KEY=piedmont
BROWSER=chrome
NERDCTL_NETWORK_MODE=host

# Optional: mount decryption config/keys for encrypted passwords.
# QA_SECRET_DIR_HOST=/secure/path/customer-qa-secrets
# QA_SECRET_DIR=/home/jenkins/qa-secrets
```

Important:

- `JENKINS_URL` must be reachable from the client server.
- `JENKINS_AGENT_NAME` must exactly match the Jenkins node name.
- `JENKINS_SECRET` must come from that Jenkins node page.
- `CUSTOMER_KEY` should match the customer selected in the Jenkins pipeline.
- `NERDCTL_NETWORK_MODE=host` is recommended for this POC because the container should use the client server's existing VPN/private routes and does not need nerdctl bridge CNI plugins.
- `QA_SECRET_DIR_HOST` should point to a secure host directory only when the QA framework needs decryption config or keys for encrypted passwords.

### 5.2 Confirm Python/Behave Requirements

The agent image includes network tools, Chromium browser dependencies, Chromium driver, and a base Python virtualenv for Behave-based automation.

For Python/Behave automation, make sure the image or job command has:

- `python3`
- `python3-pip`
- `python3-venv`
- `behave`
- Selenium dependencies used by your framework
- `cryptography` for frameworks that decrypt encrypted password values
- Chrome/Chromium driver dependency

The POC image installs the base operating-system packages and Python packages from `agent/requirements-qa-base.txt`:

```dockerfile
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    chromium \
    chromium-driver \
    python3 \
    python3-pip \
    python3-venv \
  && python3 -m venv /opt/qa-venv \
  && /opt/qa-venv/bin/pip install -r /tmp/requirements-qa-base.txt \
  && rm -rf /var/lib/apt/lists/*
```

If your QA repository has `requirements.txt`, install project-specific dependencies during the Jenkins job:

```bash
python3 -m venv --system-site-packages .venv
. .venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
```

### 5.3 Start The Agent With nerdctl

First confirm the Jenkins inbound agent base image can be pulled:

```bash
nerdctl pull jenkins/inbound-agent:latest-jdk17
```

If Docker Hub is blocked from the client server, mirror this image to your private registry and build with a custom `JENKINS_AGENT_BASE_IMAGE`.

Build and start the container:

```bash
./agent/start-agent-nerdctl.sh
```

The script performs these actions:

- loads `agent/.env`
- validates required Jenkins agent values
- builds the image with `nerdctl build`
- removes an old container with the same agent name, if one exists
- starts the inbound Jenkins agent container with `nerdctl run --net host`
- mounts a persistent work directory at `/home/jenkins/agent`
- mounts `scripts/` read-only at `/home/jenkins/agent/poc-scripts`
- mounts `QA_SECRET_DIR_HOST` read-only when it is configured
- sets `--shm-size 2g` for browser stability

The equivalent manual build command is:

```bash
nerdctl build -t qa-jenkins-inbound-agent:latest -f agent/Dockerfile .
```

To build from a private registry mirror:

```bash
nerdctl build \
  --build-arg JENKINS_AGENT_BASE_IMAGE=registry.example.com/jenkins/inbound-agent:latest-jdk17 \
  -t qa-jenkins-inbound-agent:latest \
  -f agent/Dockerfile .
```

The equivalent manual run command is:

```bash
nerdctl run -d \
  --name qa-agent-piedmont \
  --restart unless-stopped \
  --net host \
  --env-file agent/.env \
  --shm-size 2g \
  -v "$(pwd)/.agent-workdir:/home/jenkins/agent" \
  -v "$(pwd)/scripts:/home/jenkins/agent/poc-scripts:ro" \
  -v "/secure/path/customer-qa-secrets:/home/jenkins/qa-secrets:ro" \
  qa-jenkins-inbound-agent:latest \
  -url "https://jenkins.example.com/" \
  -secret "<secret from Jenkins node page>" \
  -name "qa-agent-piedmont" \
  -workDir /home/jenkins/agent
```

Prefer `./agent/start-agent-nerdctl.sh` so values come from `agent/.env`.

Check logs:

```bash
./agent/logs-agent-nerdctl.sh
```

Expected result:

```text
Agent successfully connected and online
```

Also verify in Jenkins:

1. Go to `Manage Jenkins`.
2. Open `Nodes`.
3. Open `qa-agent-piedmont`.
4. Confirm the node is online.

### 5.4 Useful Agent Commands

Stop the agent:

```bash
./agent/stop-agent-nerdctl.sh
```

Restart the agent:

```bash
./agent/stop-agent-nerdctl.sh
./agent/start-agent-nerdctl.sh
```

Rebuild after Dockerfile changes:

```bash
./agent/start-agent-nerdctl.sh
```

Open a shell inside the container:

```bash
./agent/shell-agent-nerdctl.sh
```

List running containers:

```bash
nerdctl ps
```

Show all containers, including stopped ones:

```bash
nerdctl ps -a
```

## 6. Prepare The QA Automation Command

The Jenkins pipeline calls:

```bash
./scripts/run-qa-sanity.sh
```

That wrapper expects the real QA command in `QA_TEST_COMMAND`.

For Python/Behave, the command will usually look like one of these.

Simple Behave command:

```bash
behave features --tags "${TEST_TAGS}" -D browser="${BROWSER}" -D endpoint="${TARGET_URL}" --junit --junit-directory artifacts/test-results
```

Behave command with virtual environment:

```bash
python3 -m venv --system-site-packages .venv
. .venv/bin/activate
pip install --upgrade pip
if [ -f requirements.txt ]; then pip install -r requirements.txt; fi
behave features --tags "${TEST_TAGS}" -D browser="${BROWSER}" -D endpoint="${TARGET_URL}" --junit --junit-directory artifacts/test-results
```

Behave command if your feature path is specific:

```bash
behave path/to/features/synthetic_monitoring.feature --tags "${TEST_TAGS}" -D browser="${BROWSER}" -D endpoint="${TARGET_URL}" --junit --junit-directory artifacts/test-results
```

Use the command that matches the existing QA framework.

### 6.1 Customer Tags Are Required

The daily `@synthetic_monitoring` feature contains rows for multiple customers. Do not run only `@synthetic_monitoring` from a customer-specific agent, because that can make one customer container try every customer URL.

Use a customer tag with the base tag:

```bash
@synthetic_monitoring and @customer_piedmont
```

Required tag mapping:

| Customer | Required Tag |
| --- | --- |
| `piedmont` | `@customer_piedmont` |
| `zito` | `@customer_zito` |
| `brctv` | `@customer_brctv` |
| `comporium` | `@customer_comporium` |
| `sectv` | `@customer_sectv` |
| `secv` | `@customer_secv` |
| `wow-trial` | `@customer_wow_trial` |

Split each Scenario Outline Examples table into customer-tagged Examples blocks. See `docs/customer-tagging.md`.

To generate a tagged copy for review:

```bash
./scripts/tag-synthetic-monitoring-feature.py path/to/synthetic_monitoring.feature /tmp/synthetic_monitoring.tagged.feature
```

Validate the feature before enabling daily runs:

```bash
./scripts/validate-customer-tags.sh path/to/synthetic_monitoring.feature
```

## 7. Create The Jenkins Pipeline Job

### 7.1 Create Pipeline Job

In Jenkins:

1. Click `New Item`.
2. Enter a job name:

```text
qa-vpn-sanity-poc
```

3. Select `Pipeline`.
4. Click `OK`.

### 7.2 Configure Pipeline Source

If Jenkins can read this repository:

1. Scroll to `Pipeline`.
2. Select `Pipeline script from SCM`.
3. Choose Git.
4. Enter the repository URL.
5. Set the branch.
6. Set script path:

```text
jenkins-vpn-qa-poc/Jenkinsfile
```

If you are testing manually:

1. Select `Pipeline script`.
2. Paste the content of `jenkins-vpn-qa-poc/Jenkinsfile`.

### 7.3 Confirm Customer Labels In Jenkinsfile

The `Jenkinsfile` contains this customer-to-label mapping:

```groovy
def customerLabels = [
  'piedmont': 'customer-piedmont',
  'zito': 'customer-zito',
  'brctv': 'customer-brctv',
  'comporium': 'customer-comporium',
  'sectv': 'customer-sectv',
  'secv': 'customer-secv',
  'wow-trial': 'customer-wow-trial'
]
```

Make sure each label exists on the correct Jenkins node.

Example:

```text
CUSTOMER=piedmont
```

must run on:

```text
customer-piedmont
```

The `Jenkinsfile` also validates that `TEST_TAGS` includes the selected customer tag.

### 7.4 Create Daily Fan-Out Job

Create a second Jenkins Pipeline job for the daily sanity schedule.

Recommended job name:

```text
qa-vpn-sanity-daily
```

Configure it with:

```text
Script path: jenkins-vpn-qa-poc/Jenkinsfile.daily
```

This daily job does not run Behave directly. It triggers the single-customer job once per customer and passes:

- `CUSTOMER`
- `ENVIRONMENT_URL`
- `BROWSER`
- `TEST_TAGS`
- `QA_TEST_COMMAND`

The daily job uses this schedule by default:

```text
H 6 * * *
```

Each child build runs inside that customer's Jenkins agent container.

## 8. Run The First POC Test

Open the Jenkins job and click `Build with Parameters`.

Example values:

```text
CUSTOMER: piedmont
ENVIRONMENT_URL: https://piedmont.nimblethis.net/
BROWSER: chrome
TEST_TAGS: @synthetic_monitoring and @customer_piedmont
QA_TEST_COMMAND: python3 -m venv --system-site-packages .venv
. .venv/bin/activate
pip install --upgrade pip
if [ -f requirements.txt ]; then pip install -r requirements.txt; fi
behave features --tags "${TEST_TAGS}" -D browser="${BROWSER}" -D endpoint="${TARGET_URL}" --junit --junit-directory artifacts/test-results
```

Click `Build`.

Expected pipeline stages:

1. `Validate Routing`
2. `Connectivity Check`
3. `Run QA Sanity`

## 9. Validate The Result

### 9.1 Validate Routing

In Jenkins console output, confirm:

```text
Customer: piedmont
Expected label: customer-piedmont
Expected Behave customer tag: @customer_piedmont
Behave tags: @synthetic_monitoring and @customer_piedmont
Target URL: https://piedmont.nimblethis.net/
```

Also confirm the build ran on the correct node:

```text
Running on qa-agent-piedmont
```

### 9.2 Validate Connectivity Artifacts

After the build, open archived artifacts:

```text
artifacts/connectivity/summary.txt
artifacts/connectivity/dns.txt
artifacts/connectivity/tcp.txt
artifacts/connectivity/http-headers.txt
artifacts/connectivity/tls.txt
```

Expected `summary.txt` result:

```text
Connectivity check passed
```

### 9.3 Validate Behave Test Output

Check:

```text
artifacts/logs/qa-stdout.log
artifacts/logs/qa-stderr.log
artifacts/qa-run-summary.txt
artifacts/test-results/
```

Expected:

- Behave starts successfully.
- Tests use the selected `TARGET_URL`.
- Browser starts in headless mode.
- JUnit XML files are generated under `artifacts/test-results`.
- Jenkins shows test results in the build page.

## 10. Add Credentials Safely

Do not put application passwords, VPN secrets, or Jenkins agent secrets in Git.

Recommended Jenkins credentials:

| Secret Type | Jenkins Credential Type | Example Environment Variable |
| --- | --- | --- |
| App username | Username/password | `APP_USERNAME` |
| App password | Username/password | `APP_PASSWORD` |
| API token | Secret text | `APP_TOKEN` |
| Customer CA certificate | Secret file | `CUSTOMER_CA_FILE` |

For a production-ready pipeline, wrap the QA command with Jenkins `withCredentials`.

Example:

```groovy
withCredentials([
  usernamePassword(
    credentialsId: 'piedmont-qa-login',
    usernameVariable: 'APP_USERNAME',
    passwordVariable: 'APP_PASSWORD'
  )
]) {
  sh './scripts/run-qa-sanity.sh'
}
```

Then your Behave command can read:

```bash
APP_USERNAME="${APP_USERNAME}"
APP_PASSWORD="${APP_PASSWORD}"
```

Important:

- Do not use `set -x` when secrets are present.
- Do not echo usernames/passwords.
- Keep feature files free of real passwords.

For the current POC, the feature keeps encrypted password values. The container must still receive the decryption configuration that the QA framework already uses on QA workstations.

Recommended approach:

1. Place the decryption config/key files on the client server in a secure directory.
2. Set `QA_SECRET_DIR_HOST` in `agent/.env`.
3. Start the agent with `./agent/start-agent-nerdctl.sh`.
4. The directory is mounted read-only into the container at `QA_SECRET_DIR`, default `/home/jenkins/qa-secrets`.
5. Configure the QA framework to read its decryption material from `QA_SECRET_DIR`.

## 11. Onboard Another Customer

Repeat this process for each customer.

Example for Zito:

1. Create Jenkins node:

```text
qa-agent-zito
```

2. Add label:

```text
customer-zito
```

3. Copy the new Jenkins agent secret.
4. Deploy another agent container on the Zito-accessible client server.
5. Configure `agent/.env`:

```bash
JENKINS_URL=https://jenkins.example.com/
JENKINS_AGENT_NAME=qa-agent-zito
JENKINS_SECRET=<zito node secret>
CUSTOMER_KEY=zito
BROWSER=chrome
```

6. Start the container:

```bash
./agent/start-agent-nerdctl.sh
```

7. Run Jenkins job with:

```text
CUSTOMER: zito
ENVIRONMENT_URL: https://nimble-web.zitomedia.net/
TEST_TAGS: @synthetic_monitoring and @customer_zito
```

8. Confirm the build runs on `qa-agent-zito`.

## 12. Isolation Rules

Follow these rules for the POC and production rollout:

- One customer should have one dedicated Jenkins node.
- One customer should have one dedicated Jenkins label.
- Set node executors to `1` unless parallel runs are explicitly approved.
- A job for `CUSTOMER=piedmont` must run only on `customer-piedmont`.
- Do not share one agent across multiple customer VPNs for the first rollout.
- Store customer-specific secrets separately.
- Do not allow QA users to administer Jenkins nodes or credentials unless required.

## 13. Troubleshooting

### Agent Does Not Come Online

Check container logs:

```bash
./agent/logs-agent-nerdctl.sh
```

or:

```bash
nerdctl logs -f qa-agent-piedmont
```

Common causes:

- Wrong `JENKINS_URL`.
- Wrong `JENKINS_AGENT_NAME`.
- Wrong `JENKINS_SECRET`.
- Client server cannot reach Jenkins.
- Jenkins inbound agent port or WebSocket configuration is blocked.

### Agent Container Name Is Stuck

If startup fails with an error like:

```text
failed re-acquiring name
name "qa-agent-piedmont" is already used
```

remove the stale container name:

```bash
nerdctl rm -f qa-agent-piedmont || true
nerdctl ps -a | grep qa-agent-piedmont || true
```

If the name still appears, inspect containerd directly:

```bash
nerdctl --namespace default ps -a | grep qa-agent-piedmont || true
ctr -n default containers ls | grep qa-agent-piedmont || true
ctr -n default tasks ls | grep qa-agent-piedmont || true
```

Remove the stale task/container:

```bash
ctr -n default tasks kill qa-agent-piedmont || true
ctr -n default tasks rm qa-agent-piedmont || true
ctr -n default containers rm qa-agent-piedmont || true
```

Then rerun:

```bash
./agent/start-agent-nerdctl.sh
```

### nerdctl Bridge CNI Is Missing

If startup fails with:

```text
failed to call cni.Setup: plugin type="bridge" failed (add): failed to find plugin "bridge" in path [/opt/cni/bin]
```

nerdctl is trying to use bridge networking, but CNI plugins are not installed on the client server. For this POC, use host networking:

```bash
NERDCTL_NETWORK_MODE=host
```

The start script uses host networking by default. Host networking is appropriate here because the agent container needs outbound access to Jenkins and the customer application through the client server's existing VPN/private routes. It does not need inbound ports.

If host networking is not allowed later, install and configure the required CNI plugins on the client server instead of using `--net host`.

### Agent Image Build Fails

If the build fails with an error like this:

```text
failed to resolve source metadata for docker.io/jenkins/inbound-agent:lts-jdk17
```

the base image tag is wrong or unavailable from the client server. The POC uses:

```text
jenkins/inbound-agent:latest-jdk17
```

Validate the pull:

```bash
nerdctl pull jenkins/inbound-agent:latest-jdk17
```

If the pull succeeds, rebuild:

```bash
./agent/start-agent-nerdctl.sh
```

If the pull fails because Docker Hub is blocked, mirror the image into your private registry and build with:

```bash
nerdctl build \
  --build-arg JENKINS_AGENT_BASE_IMAGE=registry.example.com/jenkins/inbound-agent:latest-jdk17 \
  -t qa-jenkins-inbound-agent:latest \
  -f agent/Dockerfile .
```

### DNS Check Fails

Run from the client server:

```bash
dig piedmont.nimblethis.net
```

or:

```bash
getent hosts piedmont.nimblethis.net
```

Common causes:

- Customer DNS is only available after VPN is connected.
- The nerdctl/containerd container is not using the expected DNS server.
- Split DNS is not configured on the client server.

Fix options:

- Configure DNS on the host.
- Configure containerd or nerdctl DNS behavior for the host.
- Add temporary `extra_hosts` entries only for POC testing.

### TCP Check Fails

Run:

```bash
nc -vz piedmont.nimblethis.net 443
```

Common causes:

- VPN route missing.
- Firewall blocking traffic.
- Wrong port.
- Application is down.

### TLS Check Fails

Common causes:

- Private CA not trusted.
- SNI mismatch.
- Certificate expired.
- TLS inspection or proxy issue.

Fix options:

- Install the customer CA certificate in the agent image.
- Confirm the URL hostname matches the certificate.
- Test with `openssl s_client`.

### Behave Command Fails

Check:

```text
artifacts/logs/qa-stdout.log
artifacts/logs/qa-stderr.log
```

Common causes:

- Python dependencies are missing.
- `behave` is not installed.
- Browser cannot start in headless mode.
- Feature path is wrong.
- Step definitions cannot read `TARGET_URL`, `BROWSER`, or credentials.

Fix options:

- Install dependencies from `requirements.txt`.
- Confirm Chrome/Chromium is installed.
- Confirm the Behave command works manually inside the agent container.

### Jenkins Does Not Show Test Results

Common causes:

- Behave did not generate JUnit XML.
- JUnit files are in a different directory.
- The pipeline archives `artifacts/test-results/**/*.xml`, but the command writes elsewhere.

Fix:

Use:

```bash
--junit --junit-directory artifacts/test-results
```

## 14. POC Acceptance Checklist

The POC is successful when all of these are true:

- Jenkins controller can trigger a job without QA laptop VPN access.
- Customer agent connects outbound to Jenkins.
- The agent runs on the customer/client server.
- The connectivity check passes for the VPN-protected URL.
- Python/Behave tests start from Jenkins.
- JUnit results are visible in Jenkins.
- Logs and artifacts are archived.
- A customer job runs only on that customer's Jenkins node.
- A second customer can be onboarded with the same pattern.

## 15. Production Recommendation

Start production rollout with static long-running inbound agents:

- One agent per customer.
- One label per customer.
- One executor per customer.
- Central Jenkins pipeline.
- Customer credentials stored in Jenkins Credentials.
- QA command kept configurable per framework.

After the POC is stable, standardize:

- Agent image versioning.
- Customer onboarding checklist.
- Credential naming convention.
- Monitoring for offline agents.
- Alerting for repeated connectivity failures.
- Regular patching of the agent image.
