# parse-csv

`parse-csv-clean` currently mirrors the same DuckDB analysis workflow as `parse-csv`: a menu-driven local toolkit for Lee County property data and similar spreadsheet exports.

## What The Current Tool Includes

- interactive DuckDB analysis over `.csv` and `.xlsx` inputs
- column normalization for common assessor-style headers
- worksheet selection for Excel workbooks
- timestamped output files for every menu action
- Gemini-assisted natural-language querying through option `L`
- Florida DFS licensee lookup through option `10`
- run logs in `script-run.log`, `analysis-results.log`, and `merge-summary.log`

## Key Files

- `analyze_csv.sh`: primary menu workflow
- `scripts/fldfs_scraper.py`: DFS lookup helper
- `scripts/spreadsheet_logger.py`: line-safe log writer
- `output/`: saved result files from prior runs
- `older-files/`: archived earlier script versions

## Local Requirements

- Bash
- DuckDB CLI
- `jq`
- `curl`
- `python3`
- Python packages needed by the DFS helper: `requests`, `beautifulsoup4`, and `lxml`

## Run It

```bash
./analyze_csv.sh [dataset-file] [sheet]
```

Typical flow:

1. load a CSV or Excel workbook
2. review row counts, schema, and sample rows
3. choose a menu option to run analysis or lookup workflows
4. inspect saved outputs under `output/`

## Important Notes

- Option `L` sends a natural-language prompt to Gemini and executes the returned DuckDB SQL.
- The current script contains a committed Gemini key value. Replace it with your own secret-handling approach before relying on the LLM path.
- This repo is effectively a sibling copy of the same workflow, not a separate product with a different runtime.
