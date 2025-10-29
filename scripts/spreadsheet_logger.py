#!/usr/bin/env python3
"""Mirror stdout while appending spreadsheet-friendly log rows."""
from __future__ import annotations

import argparse
import csv
import datetime as _dt
import os
import re
import sys
from typing import Iterable, TextIO

ANSI_CSI_RE = re.compile(r"\x1B\[[0-9;?]*[ -/]*[@-~]")
ANSI_OSC_RE = re.compile(r"\x1B\][^\x07\x1B]*(?:\x07|\x1B\\)")


def strip_ansi(value: str) -> str:
    """Remove common ANSI escape sequences from *value*."""
    without_osc = ANSI_OSC_RE.sub("", value)
    return ANSI_CSI_RE.sub("", without_osc)


def open_writer(log_path: str) -> tuple[csv.writer, TextIO]:
    directory = os.path.dirname(log_path)
    if directory:
        os.makedirs(directory, exist_ok=True)
    file_obj = open(log_path, "a", encoding="utf-8", newline="")
    writer = csv.writer(
        file_obj,
        delimiter=";",
        quoting=csv.QUOTE_MINIMAL,
        lineterminator="\n",
    )
    return writer, file_obj


def iso_timestamp() -> str:
    return _dt.datetime.now().isoformat(timespec="seconds")


def write_line(
    line: str,
    *,
    writer: csv.writer,
    sink: TextIO,
) -> None:
    sanitized = strip_ansi(line)
    writer.writerow([iso_timestamp(), sanitized])
    sink.flush()


def process_stream(
    *,
    reader: Iterable[str],
    writer: csv.writer,
    sink: TextIO,
    pass_through: bool,
) -> None:
    pending = ""
    for chunk in reader:
        if pass_through:
            sys.stdout.write(chunk)
            sys.stdout.flush()
        pending += chunk
        while True:
            newline_index = pending.find("\n")
            if newline_index == -1:
                break
            line = pending[:newline_index]
            pending = pending[newline_index + 1 :]
            write_line(
                line.rstrip("\r"),
                writer=writer,
                sink=sink,
            )
    if pending:
        tail = pending.rstrip("\r")
        write_line(
            tail,
            writer=writer,
            sink=sink,
        )
    if pass_through:
        sys.stdout.flush()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("logfile", help="Path to the log file to append to.")
    parser.add_argument(
        "--pass-through",
        action="store_true",
        help="Echo processed output to stdout while logging.",
    )
    args = parser.parse_args(argv)

    writer, handle = open_writer(args.logfile)
    try:
        process_stream(
            reader=iter(lambda: sys.stdin.read(4096), ""),
            writer=writer,
            sink=handle,
            pass_through=args.pass_through,
        )
    finally:
        handle.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
