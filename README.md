# parse-csv

Interactive DuckDB tooling for exploring Lee County property records and other delimited spreadsheets.

## Overview

This repository contains shell scripts that streamline loading parcel-level datasets into DuckDB for quick, menu-driven analysis. The primary entry point is [`analyze_csv.sh`](analyze_csv.sh), which:

- Works with large `.csv` and `.xlsx` files using DuckDB's CSV reader and Excel extension.
- Normalizes commonly used Lee County assessor column names (sale date, amount, size, owner, etc.).
- Provides a menu of prebuilt queries covering sales activity, ownership patterns, value-add opportunities, and more.
- Offers an optional "LLM" prompt that sends a natural-language request to Google Gemini, converts it to DuckDB SQL, and runs the generated query.
- Logs each run to `script-run.log`, `analysis-results.log`, and time-stamped files in the `output/` directory for later review.

## Prerequisites

The scripts assume the following tools are installed locally:

- **Bash** (uses `set -euo pipefail` and arrays).
- **DuckDB CLI** with the ability to install the Excel extension (`duckdb` command on your `PATH`).
- **jq** for JSON manipulation when talking to the LLM endpoint.
- **curl** for HTTP requests to the Gemini API.
- **python3** with the [`requests`](https://pypi.org/project/requests/), [`beautifulsoup4`](https://pypi.org/project/beautifulsoup4/), and [`lxml`](https://pypi.org/project/lxml/) packages for the new website parsing workflow.

If you plan to use the LLM workflow, you must also provide a valid Google Gemini API key.

## Usage

1. Place your CSV or Excel file in the repository directory (or reference it with a relative/absolute path when prompted).
2. Run the analysis script:

   ```bash
   ./analyze_csv.sh [dataset-file] [sheet]
   ```

   - If you omit the file argument, the script will prompt for one. When analyzing Excel workbooks you may optionally specify a sheet name or index.
   - Column mappings (sale date, sale amount, square footage, etc.) are defined near the top of the script; adjust them if your dataset uses different headers.

3. Choose a menu option to execute one of the curated DuckDB reports. Results are displayed in the terminal and saved to a timestamped log file under `output/`.

   - Option `10` triggers a guided workflow that submits a name to the Florida Department of Financial Services (DFS) licensee search portal and prints the tabular results. It relies on the helper script in `scripts/fldfs_scraper.py` and the Python dependencies listed above.

4. Select the `L` option to send a natural-language prompt to Gemini. Review and replace the hard-coded `GEMINI_API_KEY` in the script with your own key before using this feature.

5. Inspect run history via:

   ```bash
   less script-run.log
   less analysis-results.log
   ls output/
   ```

## Repository Layout

- `analyze_csv.sh` – main menu-driven analysis script (current version with Gemini prompt display and DFS website tester).
- `scripts/fldfs_scraper.py` – Python helper that handles the ASP.NET form workflow for the DFS licensee search.
- `older-files/` – archives of earlier scripts and resources.
- `ParcelListing-Lee County-20251010-1150.*` – example dataset exports used for testing.

## Security Note

The committed script currently contains a placeholder Gemini API key. Treat it as invalid and replace it with your own secret before running the LLM workflow. Never commit real API keys to version control.
