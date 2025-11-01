# parse-csv

Interactive DuckDB tooling for normalizing, inspecting, and querying large property record extracts.

## Key features

- **Multi-file ingestion** – [`analyze_csv.sh`](analyze_csv.sh) accepts one or more `.csv`, `.txt`, `.xlsx`, or `.xls` files, captures the source filename, and unions them into a single staging view.
- **Canonical schema mapping** – the loader projects incoming columns into a 120+ field `PropertyListing` table, inferring counties from filenames (with fallbacks) and generating identifiers where source data are missing.
- **Local DuckDB cache** – every run materializes a reusable `local.duckdb` database with helper views (`v_all`, `v_property_listing`, `v_raw_all`) so you can reconnect with the DuckDB CLI for ad hoc analysis.
- **Spreadsheet-friendly logging** – all stdout is mirrored to `script-run.log`, `analysis-results.log`, and `merge-summary.log` via [`scripts/spreadsheet_logger.py`](scripts/spreadsheet_logger.py), with per-menu output captured in timestamped files under `output/`.
- **Interactive metadata console** – the menu focuses on schema introspection and sampling (row counts, column definitions, first/last rows, and periodic sampling) while preserving DuckDB SQL for reuse.
- **LLM-assisted SQL drafting** – option `L` sends a structured prompt (including available columns) to Google Gemini, surfaces the exact JSON payload, handles clarification loops, and logs generated SQL alongside results.

## Prerequisites

Install the following locally before running the toolkit:

- **Bash** with support for `set -euo pipefail` and arrays.
- **DuckDB CLI** (`duckdb`) with permission to install the Excel extension when needed.
- **jq** for constructing JSON payloads.
- **curl** for REST requests to the Gemini API.
- **python3** (standard library only) for the spreadsheet logger utility. No third-party packages are required for the current menu flow.

If you intend to use the LLM integration you also need a valid Google Gemini API key.

## Quickstart

1. Place one or more export files (CSV, TSV/TXT, or Excel) in the repository root. The sample `ParcelListing-Lee County-20251010-1150.csv` is provided for testing.
2. Launch the loader, optionally specifying an initial dataset path and Excel sheet:

   ```bash
   ./analyze_csv.sh 'ParcelListing-Lee County-20251010-1150.csv'
   ```

3. Review the merge summary, then explore the menu options. Each selection writes a semicolon-delimited log file under `output/` and appends to the persistent log files for auditing.

## Usage

1. Run `./analyze_csv.sh [dataset-file] [sheet]`.
   - When no arguments are supplied the script scans the repository for compatible files and lets you pick multiple inputs at once (comma or space separated).
   - For Excel workbooks you can prefill the sheet name/index as the second argument or respond interactively when prompted for each file.
2. Confirm the inferred counties and state defaults. You can override the fallbacks by exporting `DEFAULT_COUNTY_FALLBACK` or `DEFAULT_STATE_ABBREV` before launching the script.
3. Wait for the normalization process to finish. The script writes a combined raw table plus the `PropertyListing` table into `local.duckdb`, records the mapping decisions in `merge-summary.log`, and prints dataset dimensions.
4. Choose from the on-screen menu to inspect metadata, stream row samples, or invoke the Gemini-powered SQL workflow (option `L`).
5. Revisit outputs later by inspecting `output/` or replaying the saved DuckDB SQL.

## Normalization workflow

- Source files are unioned into a staging view with an added `__source_file` column.
- A canonical schema is generated from the `PropertyListing` definition in the script. Columns are matched by normalized names and aliases; missing values fall back to defaults (auto-generated listing IDs, inferred counties, provided state abbreviations, timestamps).
- The script logs which columns mapped cleanly versus which required defaults, and reports row counts per source file.
- Views `v_all` and `v_property_listing` expose the normalized data, while `v_raw_all` retains the original field names for reference.

## Menu reference

| Option | Title | Description |
| ------ | ----- | ----------- |
| 1 | Source dataset – row/column counts | Re-reads the selected files and reports total rows and columns prior to normalization. |
| 2 | Local DuckDB – row/column counts | Displays the materialized table dimensions inside `local.duckdb`. |
| 3 | Source dataset – column details | Lists column ordinals, data types, and defaults from the staging view. |
| 4 | Local DuckDB – column details | Lists column metadata from the `PropertyListing` table. |
| 5 | Source dataset – first row (vertical view) | Shows the first record with column/value pairs for quick sanity checks. |
| 6 | Show the first 50 rows | Streams the first 50 rows from the normalized table. |
| 7 | Show the last 50 rows | Streams the last 50 rows from the normalized table. |
| 8 | Show every 20th row | Samples every twentieth record from the normalized table. |
| L | LLM prompt and analysis | Facilitates Gemini-backed SQL generation with optional clarification loops. |
| 0 | Quit | Exits the menu. |

## Logging outputs

- `script-run.log` – chronological record of terminal output (semicolon-delimited for easy spreadsheet import).
- `analysis-results.log` – appended log of menu outputs, generated SQL, and LLM transcripts.
- `merge-summary.log` – details about source file counts, mapped columns, and defaults applied during normalization.
- `output/` – individual menu result files named `menu-item_<choice>_<timestamp>.log`.

## Repository layout

- `analyze_csv.sh` – main menu-driven loader, normalization engine, and LLM interface.
- `scripts/spreadsheet_logger.py` – utility that mirrors stdout to semicolon-delimited logs.
- `older-files/` – archived versions of prior scripts or resources.
- `output/` – timestamped result files generated by menu selections and LLM runs.
- `analysis-results.log`, `merge-summary.log`, `script-run.log` – persistent logs produced by the menu workflow.

## Security reminder

A placeholder Gemini API key is committed for demonstration purposes only. Replace it with your own secret and keep the real value out of version control.

## Troubleshooting tips

- If DuckDB reports that the Excel extension is unavailable, run `duckdb -c "INSTALL 'excel'; LOAD 'excel';"` once manually to let DuckDB cache the artifact before invoking `analyze_csv.sh` again.
- When the Gemini integration fails with an authentication error, confirm that the `GEMINI_API_KEY` environment variable is set before launching the script (for example, `export GEMINI_API_KEY=sk-...`).
- To disable screen clearing, export `CLEAR_SCREEN=0`. For colorized borders, export `FORCE_COLOR=1` (honoring `NO_COLOR` and non-TTY detection).
- For noisy terminal output, pipe the script through `less -R` to preserve color while paging through the menu and results.
