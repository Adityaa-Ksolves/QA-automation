import os
from urllib.parse import urlparse

import requests
import urllib3
from behave import given, then, when


ACCEPTABLE_STATUS_CODES = {200, 201, 202, 204, 301, 302, 303, 307, 308, 401, 403}


@given("the configured customer endpoint is available")
def step_configured_endpoint(context):
    endpoint = context.config.userdata.get("endpoint") or os.environ.get("TARGET_URL")
    if not endpoint:
        raise AssertionError("No endpoint configured. Pass -D endpoint=... or set TARGET_URL.")

    parsed = urlparse(endpoint)
    if not parsed.scheme or not parsed.netloc:
        raise AssertionError(f"Invalid endpoint URL: {endpoint}")

    context.endpoint = endpoint
    context.timeout = float(os.environ.get("QA_HTTP_TIMEOUT", "60"))


@when("I request the customer endpoint")
def step_request_endpoint(context):
    urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
    try:
        context.response = requests.get(
            context.endpoint,
            allow_redirects=True,
            timeout=context.timeout,
            verify=False,
        )
    except requests.RequestException as exc:
        raise AssertionError(f"Request failed for {context.endpoint}: {exc}") from exc

    print("")
    print("  HTTP Check")
    print("  ----------")
    print(f"  Endpoint : {context.endpoint}")
    print(f"  Status   : {context.response.status_code}")
    print(f"  Final URL: {context.response.url}")


@then("the endpoint should return an acceptable HTTP status")
def step_endpoint_status(context):
    status_code = context.response.status_code
    if status_code not in ACCEPTABLE_STATUS_CODES:
        raise AssertionError(
            f"Unexpected HTTP status {status_code} for {context.endpoint}. "
            f"Accepted statuses: {sorted(ACCEPTABLE_STATUS_CODES)}"
        )
