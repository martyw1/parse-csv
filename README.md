# parse-csv

Interactive DuckDB tooling for exploring Lee County property records and other large delimited spreadsheets.

## Key Features

- **Menu-driven DuckDB analysis** – [`analyze_csv.sh`](analyze_csv.sh) loads `.csv` or `.xlsx` datasets into a temporary DuckDB view and exposes curated reports for sales trends, ownership concentration, value-add targets, and more.
- **Automatic column normalization** – the script maps expected Lee County assessor headers (sale date, sale amount, square footage, owner, etc.) so the bundled SQL queries work against new extracts with minimal editing.
- **Excel workbook support** – when you provide an `.xlsx` file you can interactively pick the worksheet (by name or index) before data are imported with DuckDB's Excel extension.
- **Robust logging** – every run appends to `script-run.log` and `analysis-results.log`, and individual query outputs are written to timestamped files under `output/` for easy auditing.
- **LLM-assisted querying** – option `L` sends a natural-language prompt to Google Gemini, echoes the constructed request, then executes the returned SQL against the loaded DuckDB view.
- **Florida DFS scraper** – option `10` delegates to [`scripts/fldfs_scraper.py`](scripts/fldfs_scraper.py) to submit a search to the Florida Department of Financial Services licensee portal and prints the results in a readable table.

## Prerequisites

Install the following locally before running the toolkit:

- **Bash** with support for `set -euo pipefail` and arrays.
- **DuckDB CLI** (`duckdb`) with permission to install the Excel extension.
- **jq** for constructing JSON payloads.
- **curl** for REST requests to the Gemini API.
- **python3** with the [`requests`](https://pypi.org/project/requests/), [`beautifulsoup4`](https://pypi.org/project/beautifulsoup4/), and [`lxml`](https://pypi.org/project/lxml/) packages to power the DFS scraping workflow.

If you intend to use the LLM integration you also need a valid Google Gemini API key.

## Usage

1. Place your CSV or Excel file in the repository (or be prepared to enter an absolute path).
2. Launch the analysis script:

   ```bash
   ./analyze_csv.sh [dataset-file] [sheet]
   ```

   - If you omit the dataset argument the script prompts for one. For Excel workbooks you may optionally provide a sheet name or index; otherwise you will be prompted interactively.
   - Column aliases (sale date, amount, square footage, building value, etc.) are defined near the top of the script—tweak them as needed for non-standard exports.

3. Review the initial metadata summary the script prints (row count, schema, sample rows), then pick from the on-screen menu. Each selection logs the SQL that ran and saves results to a unique file inside `output/`.
4. Optional workflows:
   - Choose **`L`** to send a natural-language request to Gemini. The script displays the API key, endpoint, and JSON payload before issuing the call so you can review or reproduce the request. Replace the placeholder `GEMINI_API_KEY` in the script with your own secret before relying on this feature.
   - Choose **`10`** to run the Florida DFS search helper. You will be prompted for an entity name; the Python helper validates required libraries, submits the ASP.NET form sequence, and prints a formatted table (or truncated preview for large result sets).
5. Inspect run history at any time via:

   ```bash
   less script-run.log
   less analysis-results.log
   ls output/
   ```

## Menu Reference

| Option | Report | Description |
| ------ | ------ | ----------- |
| 1 | Recent Office Sales & PPSF | Aggregates the last 24 months of sales by city/ZIP with price-per-square-foot statistics. |
| 2 | Top Owners & Portfolios | Counts properties and total square footage by owner to highlight portfolio leaders. |
| 3 | Older Inventory & Value-Add | Flags ZIP/era cohorts where building value per square foot trails the 25th percentile benchmark. |
| 4 | Out-of-Area Owners | Lists owners with property counts plus their mailing location and covered ZIP codes. |
| 5 | Size Distribution | Buckets inventory into size ranges and reports property counts and mix percentages. |
| 6 | Underperforming Assets | Identifies parcels with building value per square foot below ZIP-level quartiles. |
| 7 | Transaction Volume / Hotspots | Tallies the last three years of sales activity by geography and year. |
| 8 | Value Drivers | Computes correlation of price-per-square-foot with year built and median metrics by decade. |
| 9 | Long-Term Ownership | Highlights owners with holdings older than 10 years to surface long-term holders. |
| 10 | Florida DFS Licensee Search | Runs the external scraper to fetch licensing search results for a given entity. |
| L | LLM Prompt / Analysis | Converts natural-language prompts to DuckDB SQL using Gemini, then executes and logs the results. |

## Repository Layout

- `analyze_csv.sh` – main menu-driven analysis script (current build with Gemini prompt display and DFS integration).
- `scripts/fldfs_scraper.py` – Python helper for the DFS licensee search workflow (prints tables or JSON).
- `output/` – timestamped result files written for each menu selection or LLM request.
- `older-files/` – archived versions of prior scripts or resources.
- `ParcelListing-Lee County-20251010-1150.*` – example parcel exports for testing the DuckDB workflows.

## Security Reminder

A placeholder Gemini API key is committed for demonstration purposes only. Replace it with your own secret and keep the real value out of version control.
