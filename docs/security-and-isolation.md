# Security And Isolation

## Required Controls

- Use one Jenkins agent per customer.
- Use one Jenkins node label per customer.
- Set each customer node to one executor unless parallel testing is explicitly approved.
- Store Jenkins agent secrets outside source control.
- Store application usernames, passwords, tokens, VPN material, encrypted-password decryption config, and private CA files in Jenkins Credentials or customer-side secret storage.
- Mask credentials in Jenkins console output.
- Do not store real customer passwords in feature files.
- Restrict job permissions so QA users can run approved jobs without administering nodes or credentials.

## Network Isolation

The preferred POC placement is a client-side server that already has the required customer network access.

Each agent should be able to reach:

- Jenkins controller outbound.
- Required source repository or artifact repository, if the QA script pulls code or dependencies.
- Only that customer's protected application endpoints.

Each agent should not be able to reach:

- Other customer protected environments.
- Jenkins controller administrative interfaces beyond normal agent connectivity.
- Unrelated internal systems.

## Container Hardening

- Run as the non-root `jenkins` user during normal operation.
- Avoid `--privileged`.
- Avoid mounting the host container runtime socket, such as Docker or containerd.
- Mount only required files or directories.
- Keep the image patched.
- Add private CA certificates at build time only when required.
- Prefer read-only mounts for scripts and configuration.

## Secrets Handling

Recommended Jenkins credential types:

- Secret text for tokens.
- Username/password for application login.
- Secret file for private CA bundles or customer-specific config files.
- Secret file or customer-side secure directory for encrypted-password decryption config.

Pass secrets to the QA command using Jenkins credential bindings, then map them to environment variables expected by the test framework.

For the current POC, encrypted password values remain in the Behave feature. Mount the decryption config into the agent container read-only with `QA_SECRET_DIR_HOST`, and configure the QA framework to read from `QA_SECRET_DIR`.

Do not echo secrets. Do not use shell tracing with `set -x` in stages that handle credentials.

## Auditability

Keep these records for each run:

- Jenkins build number.
- Customer parameter.
- Jenkins node name.
- Target URL.
- Connectivity summary.
- QA command exit code.
- Test report artifacts.

This provides enough evidence to prove the test ran from the customer-scoped network path without giving individual QA workstations VPN access.
