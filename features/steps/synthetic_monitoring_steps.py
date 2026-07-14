import os
import re
import time
from urllib.parse import urlparse

import requests
import urllib3
from behave import given, then, use_step_matcher, when
from cryptography.fernet import Fernet
from selenium import webdriver
from selenium.common.exceptions import TimeoutException
from selenium.webdriver import Keys
from selenium.webdriver.chrome.options import Options as ChromeOptions
from selenium.webdriver.common.by import By
from selenium.webdriver.firefox.options import Options as FirefoxOptions
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.support.ui import Select, WebDriverWait


ACCEPTABLE_STATUS_CODES = {200, 201, 202, 204, 301, 302, 303, 307, 308, 401, 403}
DEFAULT_TIMEOUT = int(os.environ.get("QA_UI_TIMEOUT", "60"))


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
        return By.CSS_SELECTOR, f"[data-placeholder='{value}']"
    if "type=submit" in text:
        return By.CSS_SELECTOR, "[type='submit']"
    if "class=title" in text:
        return By.CSS_SELECTOR, ".title"
    if "text():=" in text:
        value = text.split("text():=", 1)[1].strip()
        return By.XPATH, f"//*[normalize-space()='{value}']"
    if "text()=" in text:
        value = text.split("text()=", 1)[1].strip()
        return By.XPATH, f"//*[normalize-space()='{value}']"
    if "text:=" in text:
        value = text.split("text:=", 1)[1].strip()
        return By.XPATH, f"//*[normalize-space()='{value}']"
    if "text~" in text:
        value = text.split("text~", 1)[1].strip()
        return By.XPATH, f"//*[contains(normalize-space(), '{value}')]"
    if "text=" in text:
        value = text.split("text=", 1)[1].split(" and ", 1)[0].strip()
        return By.XPATH, f"//*[contains(normalize-space(), '{value}')]"

    raise AssertionError(f"Unsupported locator expression: {locator_text}")


def _find(context, locator_text=None, xpath=None, timeout=None):
    by, value = _parse_locator(locator_text, xpath)
    return _wait(context, timeout).until(EC.presence_of_element_located((by, value)))


def _click(context, locator_text=None, xpath=None, timeout=None):
    by, value = _parse_locator(locator_text, xpath)
    element = _wait(context, timeout).until(EC.element_to_be_clickable((by, value)))
    element.click()
    return element


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

    return Fernet(key.encode()).decrypt(encrypted_password.encode()).decode()


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
    candidates = [
        (By.XPATH, f"//mat-select|//select"),
        (By.XPATH, f"//*[normalize-space()='{resolved_language}']"),
    ]
    for by, value in candidates:
        try:
            element = _wait(context, 5).until(EC.presence_of_element_located((by, value)))
            tag = element.tag_name.lower()
            if tag == "select":
                Select(element).select_by_visible_text(resolved_language)
            else:
                element.click()
            _print_ui_result(context, "Language", "OK", resolved_language)
            return
        except Exception:
            continue
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
    loader_xpath = (
        "//*[contains(@class,'loader') or contains(@class,'spinner') or "
        "contains(@class,'progress') or contains(@class,'mat-progress')]"
    )
    try:
        _wait(context, DEFAULT_TIMEOUT).until(EC.invisibility_of_element_located((By.XPATH, loader_xpath)))
    except TimeoutException:
        raise AssertionError("Loader icons did not disappear before timeout.")
    _print_ui_result(context, "Loaders", "CLEARED")


@then('I will wait till the "{name}" having "{locator_text}" disappears from the screen within {seconds:d} seconds')
@when('I will wait till the "{name}" having "{locator_text}" disappears from the screen within {seconds:d} seconds')
def step_wait_disappears(context, name, locator_text, seconds):
    by, value = _parse_locator(locator_text)
    _wait(context, seconds).until(EC.invisibility_of_element_located((by, value)))
    _print_ui_result(context, name, "DISAPPEARED")


@then('I make sure that "{name}" having "{locator_text}" is visible to me on the "{page_name}"')
@when('I make sure that "{name}" having "{locator_text}" is visible to me on the "{page_name}"')
def step_visible_locator(context, name, locator_text, page_name):
    by, value = _parse_locator(locator_text)
    _wait(context).until(EC.visibility_of_element_located((by, value)))
    _print_ui_result(context, name, "VISIBLE", page_name)


@then('I make sure that "{name}" is "{state}" to me on the "{page_name}" having xpath="{xpath}"')
@when('I make sure that "{name}" is "{state}" to me on the "{page_name}" having xpath="{xpath}"')
def step_visible_xpath_state(context, name, state, page_name, xpath):
    condition = EC.visibility_of_element_located((By.XPATH, xpath))
    if state.lower() != "visible":
        raise AssertionError(f"Unsupported visibility state: {state}")
    _wait(context).until(condition)
    _print_ui_result(context, name, "VISIBLE", page_name)


@then('I capture the "{attribute}" for the webelement having xpath="{xpath}" and store it in "{session_key}"')
@when('I capture the "{attribute}" for the webelement having xpath="{xpath}" and store it in "{session_key}"')
def step_capture_text(context, attribute, xpath, session_key):
    element = _find(context, xpath=xpath)
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


@when('I select "{menu_item}" from the hamburger menu')
def step_select_hamburger(context, menu_item):
    menu_xpath = (
        "//button[contains(@class,'menu') or .//*[contains(@class,'menu')] or "
        "contains(@aria-label,'menu') or contains(@aria-label,'Menu')]"
    )
    _click(context, xpath=menu_xpath)
    _click(context, locator_text=f"text={menu_item}")
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
