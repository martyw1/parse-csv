#!/usr/bin/env python3
"""Utility to submit a search request to the Florida DFS licensee search."""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from typing import Dict, Iterable, List, Optional, Tuple

import requests
from bs4 import BeautifulSoup
from requests import Response
from requests.exceptions import RequestException
from urllib.parse import urljoin

DEFAULT_BASE_URL = "https://licenseesearch.fldfs.com/"
DEFAULT_SEARCH_PATH = "Search.aspx"

USER_AGENT = (
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/129.0 Safari/537.36"
)


@dataclass
class SearchResult:
    """Represents a parsed search result row."""

    columns: List[str]

    def as_dict(self, headers: Iterable[str]) -> Dict[str, str]:
        mapping = {}
        for header, value in zip(headers, self.columns):
            mapping[header] = value
        return mapping


class FldfsScraperError(RuntimeError):
    """Raised when the scraper cannot complete the workflow."""


class FldfsScraper:
    def __init__(
        self,
        base_url: str = DEFAULT_BASE_URL,
        search_path: str = DEFAULT_SEARCH_PATH,
        timeout: int = 45,
        verbose: bool = True,
    ) -> None:
        self.base_url = base_url
        self.search_path = search_path
        self.timeout = timeout
        self.session = requests.Session()
        self.session.headers.update({"User-Agent": USER_AGENT})
        self.verbose = verbose

    def _log(self, message: str) -> None:
        if self.verbose:
            print(message, flush=True)

    # ------------------------------------------------------------------
    # Form helpers
    # ------------------------------------------------------------------
    def _fetch_initial_form(self) -> Tuple[BeautifulSoup, Response]:
        url = urljoin(self.base_url, self.search_path)
        self._log(f"[HTTP] -> GET {url}")
        try:
            resp = self.session.get(url, timeout=self.timeout)
            resp.raise_for_status()
        except RequestException as exc:  # pragma: no cover - network errors
            raise FldfsScraperError(
                f"Unable to fetch the DFS search page: {exc}"
            ) from exc

        self._log(
            f"[HTTP] <- {resp.status_code} {len(resp.content)} bytes from {resp.url}"
        )
        self._log("[HTTP] Response body (initial form):")
        self._log(resp.text)

        soup = BeautifulSoup(resp.text, "lxml")
        form = soup.find("form")
        if form is None:
            raise FldfsScraperError("Search page does not contain a <form> element.")
        self._log("[EVENT] Located search form on the DFS page.")
        return soup, resp

    def _collect_inputs(self, form: BeautifulSoup) -> Dict[str, str]:
        payload: Dict[str, str] = {}
        for tag in form.find_all("input"):
            name = tag.get("name")
            if not name:
                continue
            input_type = (tag.get("type") or "text").lower()
            if input_type == "submit":
                # Skip submit buttons by default; we add the one we actually click.
                continue
            if input_type in {"checkbox", "radio"}:
                if tag.has_attr("checked"):
                    payload[name] = tag.get("value", "on")
                continue
            payload[name] = tag.get("value", "")
        self._log(
            f"[EVENT] Collected {len(payload)} input values from the search form."
        )
        return payload

    def _detect_field_name(self, form: BeautifulSoup, hints: Iterable[str]) -> Optional[str]:
        lowered_hints = [hint.lower() for hint in hints]
        for tag in form.find_all("input"):
            name = tag.get("name", "")
            if not name:
                continue
            candidate = name.lower()
            for hint in lowered_hints:
                if hint in candidate:
                    self._log(
                        f"[EVENT] Using input field '{name}' for the entity name search."
                    )
                    return name
            element_id = tag.get("id", "").lower()
            for hint in lowered_hints:
                if hint in element_id:
                    self._log(
                        f"[EVENT] Using input field '{name}' (matched by id) for the entity name search."
                    )
                    return name
        return None

    def _detect_submit_control(self, form: BeautifulSoup) -> Tuple[str, str]:
        for tag in form.find_all(["input", "button"]):
            name = tag.get("name")
            if not name:
                continue
            value = tag.get("value") or tag.get_text(strip=True) or ""
            if "search" in value.lower() or "search" in name.lower():
                self._log(
                    f"[EVENT] Using submit control '{name}' with value '{value}'."
                )
                return name, value or "Search"
        raise FldfsScraperError("Could not find a search submit control on the page.")

    # ------------------------------------------------------------------
    def search(self, entity_name: str) -> Dict[str, object]:
        soup, response = self._fetch_initial_form()
        form = soup.find("form")
        assert form is not None

        payload = self._collect_inputs(form)

        text_field_name = self._detect_field_name(
            form, ["txtentityname", "entityname", "name", "licensee"]
        )
        if not text_field_name:
            raise FldfsScraperError(
                "Unable to automatically determine the entity search input name."
            )
        payload[text_field_name] = entity_name
        self._log(f"[EVENT] Populated entity search value: '{entity_name}'.")

        submit_name, submit_value = self._detect_submit_control(form)
        payload[submit_name] = submit_value

        # ASP.NET forms often require __EVENTTARGET and __EVENTARGUMENT to exist.
        payload.setdefault("__EVENTTARGET", "")
        payload.setdefault("__EVENTARGUMENT", "")
        payload.setdefault("__LASTFOCUS", "")

        self._log("[HTTP] Prepared POST form payload:")
        self._log(json.dumps(payload, indent=2, ensure_ascii=False))

        action = form.get("action") or response.url
        url = urljoin(response.url, action)
        self._log(f"[HTTP] -> POST {url}")
        try:
            post_resp = self.session.post(url, data=payload, timeout=self.timeout)
            post_resp.raise_for_status()
        except RequestException as exc:  # pragma: no cover - network errors
            raise FldfsScraperError(
                f"Search submission failed: {exc}"
            ) from exc

        self._log(
            f"[HTTP] <- {post_resp.status_code} {len(post_resp.content)} bytes from {post_resp.url}"
        )
        self._log("[HTTP] Response body (search results):")
        self._log(post_resp.text)

        return self._parse_results(post_resp.text)

    def _parse_results(self, html: str) -> Dict[str, object]:
        soup = BeautifulSoup(html, "lxml")
        table_hints = [
            "gvsearch",  # grid view id prefix seen on DFS site historically
            "gridview", "results", "searchresults"
        ]
        table = None
        for hint in table_hints:
            table = soup.find("table", id=lambda value: value and hint in value.lower())
            if table:
                break
        if table is None:
            # Fallback to the first tabular data structure with headers.
            for candidate in soup.find_all("table"):
                if candidate.find("th"):
                    table = candidate
                    break
        if table is None:
            raise FldfsScraperError(
                "Unable to locate a results table in the response HTML."
            )
        self._log("[EVENT] Located results table in response HTML.")

        headers = [th.get_text(strip=True) for th in table.find_all("th")]
        if not headers:
            raise FldfsScraperError(
                "Results table does not have any header cells to describe data."
            )
        self._log(f"[EVENT] Extracted headers: {headers}")

        rows: List[SearchResult] = []
        for tr in table.find_all("tr"):
            cells = tr.find_all("td")
            if not cells:
                continue
            rows.append(SearchResult([cell.get_text(strip=True) for cell in cells]))
        self._log(f"[EVENT] Parsed {len(rows)} result rows from the table.")

        results_as_dicts = [row.as_dict(headers) for row in rows]
        self._log(
            "[EVENT] Completed DFS search parsing; preparing structured result payload."
        )
        return {
            "headers": headers,
            "row_count": len(results_as_dicts),
            "rows": results_as_dicts,
        }


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Submit a DFS licensee search and print the results while echoing all HTTP "
            "requests, responses, and parsing events."
        )
    )
    parser.add_argument(
        "--entity",
        required=True,
        help="Entity name to search for on the DFS site.",
    )
    parser.add_argument(
        "--base-url",
        default=DEFAULT_BASE_URL,
        help="Base URL for the DFS site (override for testing).",
    )
    parser.add_argument(
        "--path",
        default=DEFAULT_SEARCH_PATH,
        help="Relative path to the search page (override for testing).",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Emit raw JSON instead of a formatted text table.",
    )
    parser.add_argument(
        "--max-rows",
        type=int,
        default=10,
        help="Limit the number of rows displayed in text output (default: 10).",
    )
    return parser


def print_text(results: Dict[str, object], max_rows: int) -> None:
    headers = results.get("headers", [])
    rows: List[Dict[str, str]] = results.get("rows", [])  # type: ignore[assignment]
    width = [len(h) for h in headers]
    for row in rows:
        for idx, header in enumerate(headers):
            width[idx] = max(width[idx], len(row.get(header, "")))

    def format_row(row_values: Iterable[str]) -> str:
        parts = []
        for idx, value in enumerate(row_values):
            parts.append(value.ljust(width[idx]))
        return " | ".join(parts)

    divider = "-+-".join("-" * w for w in width)
    print(format_row(headers))
    print(divider)
    for row in rows[:max_rows]:
        print(format_row(row.get(header, "") for header in headers))
    if len(rows) > max_rows:
        print(f"… truncated {len(rows) - max_rows} additional rows …")


def main(argv: Optional[List[str]] = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    scraper = FldfsScraper(base_url=args.base_url, search_path=args.path)
    try:
        results = scraper.search(args.entity)
    except FldfsScraperError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2

    if args.json:
        json.dump(results, sys.stdout, indent=2)
        print()
    else:
        print_text(results, max_rows=args.max_rows)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
