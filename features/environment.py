import os


CUSTOMER_ALIASES = {
    "piedmont": "piedmont",
    "zito": "zito",
    "brctv": "brctv",
    "comporium": "comporium",
    "sectv": "sectv",
    "secv": "secv",
    "wow-trial": "wow-trial",
    "wow_trial": "wow-trial",
    "wow trial": "wow-trial",
}


def _normalize(value):
    return CUSTOMER_ALIASES.get((value or "").strip().lower().replace("_", "-"), (value or "").strip().lower())


def _row_value(scenario, name):
    row = getattr(scenario, "_row", None)
    if not row:
        return None
    headings = list(getattr(row, "headings", []) or [])
    cells = list(getattr(row, "cells", []) or [])
    if name in headings:
        index = headings.index(name)
        if index < len(cells):
            return cells[index]
    return None


def before_scenario(context, scenario):
    context.current_scenario_name = scenario.name
    selected_customer = _normalize(os.environ.get("CUSTOMER"))
    selected_endpoint = (os.environ.get("TARGET_URL") or os.environ.get("ENVIRONMENT_URL") or "").rstrip("/")

    row_customer = _normalize(_row_value(scenario, "Server_name"))
    row_endpoint = (_row_value(scenario, "endpoint") or "").rstrip("/")

    if selected_customer and row_customer and selected_customer != row_customer:
        scenario.skip(f"Skipping {row_customer}; Jenkins selected {selected_customer}.")
        return

    if selected_endpoint and row_endpoint and selected_endpoint != row_endpoint:
        scenario.skip(f"Skipping {row_endpoint}; Jenkins selected {selected_endpoint}.")


def after_scenario(context, scenario):
    browser = getattr(context, "browser", None)
    if browser:
        browser.quit()
        context.browser = None
