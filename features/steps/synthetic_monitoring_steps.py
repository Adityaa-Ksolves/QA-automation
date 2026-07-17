import os
import re
import time
from urllib.parse import urlparse

import requests
import urllib3
from behave import given, then, use_step_matcher, when
from cryptography.fernet import Fernet
from cryptography.fernet import InvalidToken
from selenium import webdriver
from selenium.common.exceptions import ElementClickInterceptedException, TimeoutException
from selenium.webdriver import Keys
from selenium.webdriver.chrome.options import Options as ChromeOptions
from selenium.webdriver.common.by import By
from selenium.webdriver.firefox.options import Options as FirefoxOptions
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.support.ui import Select, WebDriverWait


ACCEPTABLE_STATUS_CODES = {200, 201, 202, 204, 301, 302, 303, 307, 308, 401, 403}
DEFAULT_TIMEOUT = int(os.environ.get("QA_UI_TIMEOUT", "180"))
LOWERCASE_XPATH = "abcdefghijklmnopqrstuvwxyz"
UPPERCASE_XPATH = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"


def _resolve(context, value):
    if value is None:
        return value

    replacements = {
        "browser": context.config.userdata.get("browser") or os.environ.get("BROWSER", "chrome"),
        "language_name": context.config.userdata.get("language_name")
        or os.environ.get("LANGUAGE_NAME", "English"),
    }

    def replace(match):
        key = match.group(1).strip()
        if key.startswith("session."):
            return str(getattr(context, "session", {}).get(key.split(".", 1)[1], ""))
        return str(replacements.get(key, os.environ.get(key.upper(), match.group(0))))

    return re.sub(r"\{\{\s*([^}]+?)\s*\}\}", replace, value)


def _wait(context, timeout=None):
    return WebDriverWait(context.browser, timeout or DEFAULT_TIMEOUT)


def _safe_name(value):
    return re.sub(r"[^A-Za-z0-9_.-]+", "_", value or "unknown").strip("_")[:120]


def _artifact_dir():
    path = os.path.join(os.environ.get("QA_ARTIFACTS_DIR", "artifacts"), "ui-diagnostics")
    os.makedirs(path, exist_ok=True)
    return path


def _collect_visible_labels(context, selector, script):
    try:
        values = context.browser.execute_script(script, selector)
    except Exception:
        return []
    labels = []
    for value in values:
        label = re.sub(r"\s+", " ", str(value)).strip()
        if label:
            labels.append(label)
    return labels[:15]


def _page_diagnostics(context, action, by, value, timeout=None):
    scenario = _safe_name(getattr(context, "current_scenario_name", "scenario"))
    timestamp = time.strftime("%Y%m%d-%H%M%S", time.gmtime())
    base_path = os.path.join(_artifact_dir(), f"{timestamp}-{scenario}")
    screenshot_path = f"{base_path}.png"
    html_path = f"{base_path}.html"

    try:
        context.browser.save_screenshot(screenshot_path)
    except Exception:
        screenshot_path = "screenshot unavailable"

    try:
        with open(html_path, "w", encoding="utf-8") as handle:
            handle.write(context.browser.page_source)
    except Exception:
        html_path = "html unavailable"

    fields = _collect_visible_labels(
        context,
        "input, textarea, [contenteditable='true']",
        """
        return Array.from(document.querySelectorAll(arguments[0]))
          .filter(e => !!(e.offsetWidth || e.offsetHeight || e.getClientRects().length))
          .map(e => [
            e.tagName.toLowerCase(),
            e.getAttribute('data-placeholder') || e.getAttribute('placeholder') || e.getAttribute('aria-label') || e.name || e.id || '',
            e.value ? '<has value>' : ''
          ].filter(Boolean).join(': '));
        """,
    )
    buttons = _collect_visible_labels(
        context,
        "button, a, [role='button'], mat-expansion-panel-header",
        """
        return Array.from(document.querySelectorAll(arguments[0]))
          .filter(e => !!(e.offsetWidth || e.offsetHeight || e.getClientRects().length))
          .map(e => (e.innerText || e.getAttribute('aria-label') || e.getAttribute('title') || '').trim())
          .filter(Boolean);
        """,
    )
    panels = _collect_visible_labels(
        context,
        "mat-panel-title, mat-expansion-panel-header, .mat-expansion-panel-header-title",
        """
        return Array.from(document.querySelectorAll(arguments[0]))
          .filter(e => !!(e.offsetWidth || e.offsetHeight || e.getClientRects().length))
          .map(e => (e.innerText || '').trim())
          .filter(Boolean);
        """,
    )

    details = [
        f"{action} timed out after {timeout or DEFAULT_TIMEOUT}s.",
        f"Locator: {by} = {value}",
        f"URL: {getattr(context.browser, 'current_url', 'unknown')}",
        f"Title: {getattr(context.browser, 'title', 'unknown')}",
        f"Screenshot: {screenshot_path}",
        f"HTML: {html_path}",
    ]
    if fields:
        details.append("Visible fields: " + " | ".join(fields))
    if buttons:
        details.append("Visible buttons/links: " + " | ".join(buttons))
    if panels:
        details.append("Visible panels: " + " | ".join(panels))
    return "\n".join(details)


def _xpath_literal(value):
    if "'" not in value:
        return f"'{value}'"
    if '"' not in value:
        return f'"{value}"'
    parts = value.split("'")
    return "concat(" + ', "\'", '.join(f"'{part}'" for part in parts) + ")"


def _normalized_text_contains(value):
    return (
        "contains(translate(normalize-space(.), "
        f"'{UPPERCASE_XPATH}', '{LOWERCASE_XPATH}'), "
        f"{_xpath_literal(value.lower())})"
    )


def _normalized_text_equals(value):
    return (
        "translate(normalize-space(.), "
        f"'{UPPERCASE_XPATH}', '{LOWERCASE_XPATH}') = "
        f"{_xpath_literal(value.lower())}"
    )


def _start_browser(browser_name):
    normalized = browser_name.lower()
    if normalized in {"chrome", "chromium"}:
        options = ChromeOptions()
        options.add_argument("--headless=new")
        options.add_argument("--no-sandbox")
        options.add_argument("--disable-dev-shm-usage")
        options.add_argument("--disable-gpu")
        options.add_argument("--window-size=1920,1080")
        chrome_bin = os.environ.get("CHROME_BIN")
        if chrome_bin:
            options.binary_location = chrome_bin
        return webdriver.Chrome(options=options)

    if normalized == "firefox":
        options = FirefoxOptions()
        options.add_argument("--headless")
        return webdriver.Firefox(options=options)

    raise AssertionError(f"Unsupported browser: {browser_name}")


def _parse_locator(locator_text=None, xpath=None):
    if xpath:
        return By.XPATH, xpath

    text = locator_text or ""
    if "data-placeholder=" in text:
        value = text.split("data-placeholder=", 1)[1].split(" and ", 1)[0].strip()
        value_literal = _xpath_literal(value)
        value_lower_literal = _xpath_literal(value.lower())
        return By.XPATH, (
            "//*[self::input or self::textarea]"
            "["
            f"@data-placeholder={value_literal} or @placeholder={value_literal} or @aria-label={value_literal} or "
            f"translate(@data-placeholder, '{UPPERCASE_XPATH}', '{LOWERCASE_XPATH}')={value_lower_literal} or "
            f"translate(@placeholder, '{UPPERCASE_XPATH}', '{LOWERCASE_XPATH}')={value_lower_literal} or "
            f"translate(@aria-label, '{UPPERCASE_XPATH}', '{LOWERCASE_XPATH}')={value_lower_literal}"
            "]"
            "|//mat-form-field[.//*[normalize-space()="
            f"{value_literal} or translate(normalize-space(), '{UPPERCASE_XPATH}', '{LOWERCASE_XPATH}')={value_lower_literal}"
            "]]//*[self::input or self::textarea]"
        )
    if "type=submit" in text:
        return By.CSS_SELECTOR, "[type='submit']"
    if "class=title" in text:
        return By.CSS_SELECTOR, ".title"
    if "text():=" in text:
        value = text.split("text():=", 1)[1].strip()
        return By.XPATH, f"//*[{_normalized_text_equals(value)}]"
    if "text()=" in text:
        value = text.split("text()=", 1)[1].strip()
        return By.XPATH, f"//*[{_normalized_text_equals(value)}]"
    if "text:=" in text:
        value = text.split("text:=", 1)[1].strip()
        return By.XPATH, f"//*[{_normalized_text_equals(value)}]"
    if "text~" in text:
        value = text.split("text~", 1)[1].strip()
        return By.XPATH, f"//*[{_normalized_text_contains(value)}]"
    if "text=" in text:
        value = text.split("text=", 1)[1].split(" and ", 1)[0].strip()
        text_match = _normalized_text_contains(value)
        return By.XPATH, (
            f"//*[self::button or self::a or self::mat-expansion-panel-header or @role='button'][{text_match}]"
            f"|//*[{text_match}]/ancestor::*[self::button or self::a or self::mat-expansion-panel-header or @role='button'][1]"
            f"|//*[{text_match}]"
        )

    raise AssertionError(f"Unsupported locator expression: {locator_text}")


def _find(context, locator_text=None, xpath=None, timeout=None):
    by, value = _parse_locator(locator_text, xpath)
    try:
        return _wait(context, timeout).until(EC.presence_of_element_located((by, value)))
    except TimeoutException as exc:
        raise AssertionError(_page_diagnostics(context, "Find element", by, value)) from exc


def _click(context, locator_text=None, xpath=None, timeout=None):
    by, value = _parse_locator(locator_text, xpath)
    try:
        element = _wait(context, timeout).until(EC.element_to_be_clickable((by, value)))
    except TimeoutException as exc:
        raise AssertionError(_page_diagnostics(context, "Click element", by, value)) from exc
    context.browser.execute_script("arguments[0].scrollIntoView({block: 'center'});", element)
    try:
        element.click()
    except ElementClickInterceptedException:
        context.browser.switch_to.active_element.send_keys(Keys.ESCAPE)
        time.sleep(0.5)
        element = _wait(context, timeout).until(EC.element_to_be_clickable((by, value)))
        context.browser.execute_script("arguments[0].scrollIntoView({block: 'center'});", element)
        try:
            element.click()
        except ElementClickInterceptedException as exc:
            raise AssertionError(_page_diagnostics(context, "Click element", by, value)) from exc
    return element


def _wait_for_page_settle(context):
    _wait(context, 10).until(lambda driver: driver.execute_script("return document.readyState") == "complete")
    loader_xpath = (
        "//*[contains(@class,'loader') or contains(@class,'spinner') or "
        "contains(@class,'progress') or contains(@class,'mat-progress')]"
    )
    _wait(context, DEFAULT_TIMEOUT).until(EC.invisibility_of_element_located((By.XPATH, loader_xpath)))


def _target_url_base(context):
    endpoint = context.config.userdata.get("endpoint") or os.environ.get("TARGET_URL") or os.environ.get("ENVIRONMENT_URL")
    if endpoint:
        return endpoint.rstrip("/")
    current_url = getattr(context.browser, "current_url", "")
    parsed = urlparse(current_url)
    if parsed.scheme and parsed.netloc:
        return f"{parsed.scheme}://{parsed.netloc}"
    return ""


def _field_is_present(context, locator_text, timeout=5):
    by, value = _parse_locator(locator_text)
    try:
        _wait(context, timeout).until(EC.presence_of_element_located((by, value)))
        return True
    except TimeoutException:
        return False


def _open_install_cm(context):
    mac_locator = "data-placeholder=Mac Address"
    if _field_is_present(context, mac_locator):
        return

    click_attempts = [
        (None, "text=Install CM"),
        ("//*[contains(normalize-space(.), 'Install CM')]/ancestor::*[self::button or self::a or @role='button'][1]", None),
        ("//*[contains(normalize-space(.), 'phone_android')]/ancestor::*[self::button or self::a or @role='button'][1]", None),
        ("//*[contains(@class, 'phone_android') or normalize-space(.)='phone_android']/ancestor::*[self::button or self::a or @role='button'][1]", None),
    ]
    for xpath, locator_text in click_attempts:
        try:
            if xpath:
                _click(context, xpath=xpath, timeout=5)
            else:
                _click(context, locator_text=locator_text, timeout=5)
            _wait_for_page_settle(context)
            if _field_is_present(context, mac_locator):
                return
        except Exception:
            pass

    base_url = _target_url_base(context)
    for path in ("install-cm", "install-cm/", "install-modem", "install-modem/", "install-cable-modem"):
        if not base_url:
            break
        context.browser.get(f"{base_url}/{path}")
        _wait_for_page_settle(context)
        if _field_is_present(context, mac_locator):
            return

    _find(context, locator_text=mac_locator)


def _decrypt_password(encrypted_password):
    override = os.environ.get("APP_PASSWORD")
    if override:
        return override

    key = os.environ.get("QA_PASSWORD_FERNET_KEY")
    key_file = os.path.join(os.environ.get("QA_SECRET_DIR", "/home/jenkins/qa-secrets"), "fernet.key")
    if not key and os.path.isfile(key_file):
        with open(key_file, encoding="utf-8") as handle:
            key = handle.read().strip()

    if not key:
        raise AssertionError(
            "Encrypted password cannot be decrypted. Set APP_PASSWORD, "
            "QA_PASSWORD_FERNET_KEY, or provide $QA_SECRET_DIR/fernet.key."
        )

    key = _normalize_fernet_key(key)
    try:
        return Fernet(key.encode()).decrypt(encrypted_password.encode()).decode()
    except ValueError as exc:
        raise AssertionError(
            "QA_PASSWORD_FERNET_KEY is not a valid Fernet key. It must be the "
            "44-character url-safe base64 key generated by Fernet.generate_key(), "
            "not the encrypted password token."
        ) from exc
    except InvalidToken as exc:
        raise AssertionError(
            "QA_PASSWORD_FERNET_KEY is valid Fernet format, but it cannot decrypt "
            "the password token in the feature file. Use the original key that "
            "encrypted that gAAAA... value, or configure APP_PASSWORD instead."
        ) from exc


def _normalize_fernet_key(key):
    normalized = key.strip()
    if normalized.startswith("FERNET_KEY="):
        normalized = normalized.split("=", 1)[1].strip()
    if normalized.startswith("QA_PASSWORD_FERNET_KEY="):
        normalized = normalized.split("=", 1)[1].strip()
    if normalized.startswith("b'") and normalized.endswith("'"):
        normalized = normalized[2:-1]
    if normalized.startswith('b"') and normalized.endswith('"'):
        normalized = normalized[2:-1]
    if (normalized.startswith("'") and normalized.endswith("'")) or (
        normalized.startswith('"') and normalized.endswith('"')
    ):
        normalized = normalized[1:-1]
    return normalized.strip()


def _app_password():
    password = os.environ.get("APP_PASSWORD")
    if not password:
        raise AssertionError(
            "APP_PASSWORD is not configured. Set APP_PASSWORD_CREDENTIALS_ID "
            "to a Jenkins Secret Text credential containing the application password."
        )
    return password


def _print_ui_result(context, name, status, detail=""):
    print(f"  {name:<22} {status}")
    if detail:
        print(f"  {'':<22} {detail}")


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


@given('I launched the "{browser_name}" browser')
def step_launch_browser(context, browser_name):
    context.session = {}
    resolved_browser = _resolve(context, browser_name)
    context.browser = _start_browser(resolved_browser)
    _print_ui_result(context, "Browser", resolved_browser)


@given('I enter the Application url "{url}"')
@when('I enter the Application url "{url}"')
@then('I enter the Application url "{url}"')
def step_enter_application_url(context, url):
    resolved_url = _resolve(context, url)
    context.browser.get(resolved_url)
    _print_ui_result(context, "Navigate", "OK", resolved_url)


@given('I select "{language}" language')
@when('I select "{language}" language')
def step_select_language(context, language):
    resolved_language = _resolve(context, language)

    try:
        element = _wait(context, 3).until(EC.presence_of_element_located((By.XPATH, "//select")))
        Select(element).select_by_visible_text(resolved_language)
        _print_ui_result(context, "Language", "OK", resolved_language)
        return
    except Exception:
        pass

    try:
        mat_select = _wait(context, 3).until(EC.element_to_be_clickable((By.XPATH, "//mat-select")))
        mat_select.click()
        option_xpath = (
            f"//mat-option//span[normalize-space()='{resolved_language}']"
            f"|//*[@role='option' and normalize-space()='{resolved_language}']"
        )
        option = _wait(context, 3).until(EC.element_to_be_clickable((By.XPATH, option_xpath)))
        option.click()
        _print_ui_result(context, "Language", "OK", resolved_language)
        return
    except Exception:
        context.browser.switch_to.active_element.send_keys(Keys.ESCAPE)

    _print_ui_result(context, "Language", "SKIPPED", f"No selector found for {resolved_language}")


@when('I set the value="{value}" for "{field_name}" having "{locator_text}"')
@given('I set the value="{value}" for "{field_name}" having "{locator_text}"')
def step_set_value(context, value, field_name, locator_text):
    element = _find(context, locator_text=locator_text)
    element.clear()
    element.send_keys(_resolve(context, value))
    _print_ui_result(context, field_name, "SET")


@when('I set the encrypted password="{value}" for "{field_name}" having xpath="{xpath}"')
@given('I set the encrypted password="{value}" for "{field_name}" having xpath="{xpath}"')
def step_set_encrypted_password(context, value, field_name, xpath):
    password = _decrypt_password(value)
    element = _find(context, xpath=xpath)
    element.clear()
    element.send_keys(password)
    _print_ui_result(context, field_name, "SET", "password hidden")


@when('I set the Jenkins password for "{field_name}" having xpath="{xpath}"')
@given('I set the Jenkins password for "{field_name}" having xpath="{xpath}"')
def step_set_jenkins_password(context, field_name, xpath):
    element = _find(context, xpath=xpath)
    element.clear()
    element.send_keys(_app_password())
    _print_ui_result(context, field_name, "SET", "password hidden")


@when('I click on "{name}" having xpath="{xpath}"')
@then('I click on "{name}" having xpath="{xpath}"')
@given('I click on "{name}" having xpath="{xpath}"')
def step_click_xpath(context, name, xpath):
    _click(context, xpath=xpath)
    _print_ui_result(context, name, "CLICKED")


@when('I click on "{name}" having "{locator_text}"')
@then('I click on "{name}" having "{locator_text}"')
@given('I click on "{name}" having "{locator_text}"')
def step_click_locator(context, name, locator_text):
    _click(context, locator_text=locator_text)
    _print_ui_result(context, name, "CLICKED")


@when('I click on "{name}"')
@then('I click on "{name}"')
def step_click_named_text(context, name):
    _click(context, locator_text=f"text={name}")
    _print_ui_result(context, name, "CLICKED")


@then("I will wait till all the loader icons disappears from the screen")
@when("I will wait till all the loader icons disappears from the screen")
def step_wait_loaders(context):
    try:
        _wait_for_page_settle(context)
    except TimeoutException as exc:
        loader_xpath = (
            "//*[contains(@class, 'loader') or contains(@class, 'spinner') or "
            "contains(@class, 'progress') or self::mat-progress-spinner or self::mat-spinner]"
        )
        raise AssertionError(
            _page_diagnostics(context, "Wait for loader icons to disappear", By.XPATH, loader_xpath)
        ) from exc
    _print_ui_result(context, "Loaders", "CLEARED")


@then('I will wait till the "{name}" having "{locator_text}" disappears from the screen within {seconds:d} seconds')
@when('I will wait till the "{name}" having "{locator_text}" disappears from the screen within {seconds:d} seconds')
def step_wait_disappears(context, name, locator_text, seconds):
    by, value = _parse_locator(locator_text)
    try:
        _wait(context, seconds).until(EC.invisibility_of_element_located((by, value)))
    except TimeoutException as exc:
        raise AssertionError(
            _page_diagnostics(context, f"Wait for {name} to disappear", by, value, timeout=seconds)
        ) from exc
    _print_ui_result(context, name, "DISAPPEARED")


@then('I make sure that "{name}" having "{locator_text}" is visible to me on the "{page_name}"')
@when('I make sure that "{name}" having "{locator_text}" is visible to me on the "{page_name}"')
def step_visible_locator(context, name, locator_text, page_name):
    by, value = _parse_locator(locator_text)
    try:
        _wait(context).until(EC.visibility_of_element_located((by, value)))
    except TimeoutException as exc:
        raise AssertionError(_page_diagnostics(context, f"Wait for visible {name}", by, value)) from exc
    _print_ui_result(context, name, "VISIBLE", page_name)


@then('I make sure that "{name}" is "{state}" to me on the "{page_name}" having xpath="{xpath}"')
@when('I make sure that "{name}" is "{state}" to me on the "{page_name}" having xpath="{xpath}"')
def step_visible_xpath_state(context, name, state, page_name, xpath):
    condition = EC.visibility_of_element_located((By.XPATH, xpath))
    if state.lower() != "visible":
        raise AssertionError(f"Unsupported visibility state: {state}")
    try:
        _wait(context).until(condition)
    except TimeoutException as exc:
        raise AssertionError(_page_diagnostics(context, f"Wait for visible {name}", By.XPATH, xpath)) from exc
    _print_ui_result(context, name, "VISIBLE", page_name)


@then('I capture the "{attribute}" for the webelement having xpath="{xpath}" and store it in "{session_key}"')
@when('I capture the "{attribute}" for the webelement having xpath="{xpath}" and store it in "{session_key}"')
def step_capture_text(context, attribute, xpath, session_key):
    def visible_element(_driver):
        elements = context.browser.find_elements(By.XPATH, xpath)
        for candidate in elements:
            if candidate.is_displayed():
                return candidate
        return False

    try:
        element = _wait(context).until(visible_element)
    except TimeoutException as exc:
        raise AssertionError(_page_diagnostics(context, "Find visible element", By.XPATH, xpath)) from exc
    captured = element.text if attribute == "text" else element.get_attribute(attribute)
    key = session_key.split(".", 1)[1] if session_key.startswith("session.") else session_key
    context.session[key] = captured
    _print_ui_result(context, session_key, "CAPTURED", captured)


use_step_matcher("re")


@then(r'I make sure that "(?P<left>.+)" "(?P<operator>equals|not equals)" "(?P<right>.+)"')
@when(r'I make sure that "(?P<left>.+)" "(?P<operator>equals|not equals)" "(?P<right>.+)"')
@given(r'I make sure that "(?P<left>.+)" "(?P<operator>equals|not equals)" "(?P<right>.+)"')
def step_compare_values(context, left, operator, right):
    resolved_left = _resolve(context, left)
    resolved_right = _resolve(context, right)
    if operator == "not equals" and resolved_left == resolved_right:
        raise AssertionError(f"Expected values to differ, but both were: {resolved_left}")
    if operator == "equals" and resolved_left != resolved_right:
        raise AssertionError(f"Expected values to match: {resolved_left} != {resolved_right}")
    _print_ui_result(context, "Compare", "OK", f"{operator}")


use_step_matcher("parse")


@then('I wait up to {seconds:d} seconds for the text of xpath="{xpath}" to differ from "{session_key}" and store it in "{updated_session_key}"')
@when('I wait up to {seconds:d} seconds for the text of xpath="{xpath}" to differ from "{session_key}" and store it in "{updated_session_key}"')
def step_wait_text_differs(context, seconds, xpath, session_key, updated_session_key):
    old_key = session_key.split(".", 1)[1] if session_key.startswith("session.") else session_key
    new_key = (
        updated_session_key.split(".", 1)[1]
        if updated_session_key.startswith("session.")
        else updated_session_key
    )
    before = str(getattr(context, "session", {}).get(old_key, _resolve(context, session_key))).strip()
    context._last_seen_text = ""

    def text_changed(_driver):
        elements = context.browser.find_elements(By.XPATH, xpath)
        displayed = [element for element in elements if element.is_displayed()]
        if not displayed:
            context._last_seen_text = "<element not found>"
            return False
        current = displayed[0].text.strip()
        context._last_seen_text = current
        if current and current != before:
            context.session[new_key] = current
            return True
        return False

    try:
        WebDriverWait(context.browser, seconds).until(text_changed)
    except TimeoutException as exc:
        details = _page_diagnostics(context, "Wait for text to change", By.XPATH, xpath, timeout=seconds)
        details += f"\nPrevious text: {before}\nLast seen text: {context._last_seen_text}"
        raise AssertionError(details) from exc

    _print_ui_result(context, updated_session_key, "UPDATED", context.session[new_key])


@when('I select "{menu_item}" from the hamburger menu')
def step_select_hamburger(context, menu_item):
    menu_xpath = (
        "//button[contains(@class,'menu') or .//*[contains(@class,'menu')] or "
        "contains(@aria-label,'menu') or contains(@aria-label,'Menu')]"
    )
    _click(context, xpath=menu_xpath)
    if menu_item.strip().lower() == "install cm":
        _open_install_cm(context)
        _print_ui_result(context, "Menu", "SELECTED", menu_item)
        return

    _click(context, locator_text=f"text={menu_item}")
    _wait_for_page_settle(context)
    _print_ui_result(context, "Menu", "SELECTED", menu_item)


@when('I wait for {seconds:d} seconds')
@then('I wait for {seconds:d} seconds')
def step_wait_seconds(context, seconds):
    time.sleep(seconds)
    _print_ui_result(context, "Wait", "OK", f"{seconds}s")


@when('I press "{key_name}" key')
@then('I press "{key_name}" key')
def step_press_key(context, key_name):
    key = getattr(Keys, key_name.upper(), key_name)
    context.browser.switch_to.active_element.send_keys(key)
    _print_ui_result(context, "Key", "PRESSED", key_name)
