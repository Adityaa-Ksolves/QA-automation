#!/usr/bin/env python3
"""Split SyntheticMonitoring Examples tables into customer-tagged blocks.

Usage:
  tag-synthetic-monitoring-feature.py input.feature output.feature

The script groups rows by the Scenario Outline column named Server_name and
emits one tagged Examples block per customer. It does not decrypt, alter, or log
password values; it only moves complete table rows into tagged groups.
"""

from __future__ import annotations

import re
import sys
from collections import OrderedDict
from pathlib import Path


CUSTOMER_TAGS = {
    "piedmont": "@customer_piedmont",
    "zito": "@customer_zito",
    "brctv": "@customer_brctv",
    "comporium": "@customer_comporium",
    "sectv": "@customer_sectv",
    "secv": "@customer_secv",
    "wow-trial": "@customer_wow_trial",
}

DISPLAY_NAMES = {
    "piedmont": "Piedmont",
    "zito": "Zito",
    "brctv": "BRCTV",
    "comporium": "Comporium",
    "sectv": "Sectv",
    "secv": "Secv",
    "wow-trial": "Wow-trial",
}


def normalize_customer(value: str) -> str:
    normalized = value.strip().lower().replace("_", "-")
    aliases = {
        "wow trial": "wow-trial",
        "wow-trial": "wow-trial",
        "wow_trial": "wow-trial",
    }
    return aliases.get(normalized, normalized)


def split_cells(table_body: str) -> list[str]:
    return [cell.strip() for cell in table_body.strip().strip("|").split("|")]


def format_cells(cells: list[str], indent: str, commented: bool) -> str:
    row = f"{indent}| " + " | ".join(cells) + " |\n"
    if commented:
        return f"{indent}# " + row[len(indent) :]
    return row


def parse_table_row(line: str) -> tuple[str, list[str], bool] | None:
    active = re.match(r"^(\s*)\|(.*)\|\s*$", line)
    if active:
        return active.group(1), split_cells(active.group(2)), False

    commented = re.match(r"^(\s*)#\s*\|(.*)\|\s*$", line)
    if commented:
        return commented.group(1), split_cells(commented.group(2)), True

    return None


def transform_examples(block: list[str]) -> list[str]:
    examples_line = block[0]
    examples_match = re.match(r"^(\s*)Examples:", examples_line)
    if not examples_match:
        return block

    examples_indent = examples_match.group(1)
    table_rows: list[tuple[str, list[str], bool]] = []
    passthrough: list[str] = []

    for line in block[1:]:
        parsed = parse_table_row(line)
        if parsed:
            table_rows.append(parsed)
        elif not table_rows and not line.strip():
            passthrough.append(line)
        elif line.strip():
            return block
        else:
            passthrough.append(line)

    if len(table_rows) < 2:
        return block

    header_indent, header, _ = table_rows[0]
    try:
        server_index = [cell.lower() for cell in header].index("server_name")
    except ValueError:
        return block

    grouped: "OrderedDict[str, list[tuple[list[str], bool]]]" = OrderedDict()

    for _, cells, commented in table_rows[1:]:
        if server_index >= len(cells):
            return block
        customer = normalize_customer(cells[server_index])
        if customer not in CUSTOMER_TAGS:
            return block
        grouped.setdefault(customer, []).append((cells, commented))

    output: list[str] = []
    for customer, rows in grouped.items():
        active_rows = [(cells, commented) for cells, commented in rows if not commented]
        output.extend(passthrough)

        if active_rows:
            output.append(f"{examples_indent}{CUSTOMER_TAGS[customer]}\n")
            output.append(f"{examples_indent}Examples: {DISPLAY_NAMES[customer]}\n")
            output.append(format_cells(header, header_indent, commented=False))
            for cells, commented in rows:
                output.append(format_cells(cells, header_indent, commented=commented))
        else:
            output.append(f"{examples_indent}# Disabled {CUSTOMER_TAGS[customer]} rows from original Examples\n")
            output.append(f"{examples_indent}# Examples: {DISPLAY_NAMES[customer]}\n")
            output.append(format_cells(header, header_indent, commented=True))
            for cells, _ in rows:
                output.append(format_cells(cells, header_indent, commented=True))
        output.append("\n")

    if output and output[-1] == "\n":
        output.pop()
    return output


def transform_feature(lines: list[str]) -> list[str]:
    output: list[str] = []
    index = 0

    while index < len(lines):
        if re.match(r"^\s*Examples:", lines[index]):
            block = [lines[index]]
            index += 1
            while index < len(lines):
                line = lines[index]
                if re.match(r"^\s*(Scenario|Scenario Outline|Examples|Feature|Rule|Background):", line):
                    break
                if re.match(r"^\s*@\S+", line):
                    break
                block.append(line)
                index += 1
            output.extend(transform_examples(block))
        else:
            output.append(lines[index])
            index += 1

    return output


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__.strip(), file=sys.stderr)
        return 2

    input_path = Path(sys.argv[1])
    output_path = Path(sys.argv[2])

    if not input_path.is_file():
        print(f"Input feature file not found: {input_path}", file=sys.stderr)
        return 2

    lines = input_path.read_text(encoding="utf-8").splitlines(keepends=True)
    output_path.write_text("".join(transform_feature(lines)), encoding="utf-8")
    print(f"Wrote tagged feature to {output_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
