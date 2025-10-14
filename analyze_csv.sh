#!/usr/bin/env bash
# analyze_office_menu_with_llm_show_prompt.sh
# Version: adds display of prompt and API key when using LLM menu option

# -- created by Martin Wolfe

set -euo pipefail
IFS=$'\n'

LOGFILE="script-run.log"
ANALYSIS_LOG="analysis-results.log"
OUTDIR="output"

# Your actual API key (hardcoded as requested)
GEMINI_API_KEY="AIzaSyDCuNdhjqtH20jLbuxtpOd4tMgy-mCe5Ak"

# Choose the Gemini model to use
# You can change this to e.g. gemini-2.5-flash, gemini-1.5-pro, etc.
GEMINI_MODEL="models/gemini-2.5-flash"

# Endpoint for Gemini generateContent (REST) per Google docs:
# https://generativelanguage.googleapis.com/v1beta/{model}:generateContent
GEMINI_ENDPOINT="https://generativelanguage.googleapis.com/v1beta/${GEMINI_MODEL}:generateContent"

# Function to log and also echo a message
note () { echo "$*" | tee -a "$ANALYSIS_LOG" >/dev/null; }
sql_quote() { printf "%s" "$1" | sed "s/'/''/g"; }

exec > >(tee -a "$LOGFILE") 2>&1

echo "────────────────────────────────────────────────────────"
echo "Office Analysis & LLM Menu — $(date)"
echo "Run log: $LOGFILE"
echo "Analysis log: $ANALYSIS_LOG"
echo "────────────────────────────────────────────────────────"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_INPUT="${1:-}"

# When a default input is provided, only keep the basename so that
# prompting remains relative to the script directory as requested.
if [[ -n "$DEFAULT_INPUT" ]]; then
  DEFAULT_INPUT="$(basename "$DEFAULT_INPUT")"
fi

while true; do
  if [[ -n "$DEFAULT_INPUT" ]]; then
    read -r -p "Enter dataset file name located in $SCRIPT_DIR [${DEFAULT_INPUT}]: " SRC_BASENAME
    SRC_BASENAME="${SRC_BASENAME:-$DEFAULT_INPUT}"
  else
    read -r -p "Enter dataset file name located in $SCRIPT_DIR: " SRC_BASENAME
  fi

  if [[ -z "$SRC_BASENAME" ]]; then
    echo "A file name is required. Please try again."
    continue
  fi

  if [[ "$SRC_BASENAME" == /* ]]; then
    SRC="$SRC_BASENAME"
  else
    SRC="$SCRIPT_DIR/$SRC_BASENAME"
  fi

  if [[ -f "$SRC" ]]; then
    break
  fi

  echo "ERROR: File not found in script directory: $SRC_BASENAME"
  DEFAULT_INPUT=""
done

EXCEL_SHEET="${2:-}"

mkdir -p "$OUTDIR"

make_output_file() {
  local menu_choice="$1"
  local timestamp
  timestamp="$(date +%Y%m%d-%H%M%S)"
  printf "%s/menu-item_%s_%s.log" "$OUTDIR" "$menu_choice" "$timestamp"
}

if ! command -v duckdb >/dev/null 2>&1; then
  echo "ERROR: duckdb CLI not installed"
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required to parse JSON. Install via `brew install jq`."
  exit 1
fi

# Your spreadsheet column names
COL_SALE_DATE="SaleDate"
COL_SALE_AMOUNT="SaleAmount"
COL_GROSS_AREA="GrossArea"
COL_BUILDING_VALUE="BuildingValue"
COL_LAND_VALUE="LandValue"
COL_YEAR_BUILT="YearBuilt"
COL_CITY="SiteCity"
COL_ZIP="SiteZIP"
COL_OWNER="OwnerName"
COL_LAND_CODE="LandCode"
COL_TOTAL_VALUE="TotalLivingArea"

EXT="${SRC##*.}"
EXT_LOWER="$(printf "%s" "$EXT" | tr '[:upper:]' '[:lower:]')"
SRC_ESCAPED="$(sql_quote "$SRC")"

if [[ "$EXT_LOWER" == "xlsx" ]]; then
  if [[ -z "$EXCEL_SHEET" ]]; then
    read -r -p "Enter Excel sheet name or index to load (press Enter for the first sheet): " EXCEL_SHEET
  else
    read -r -p "Enter Excel sheet name or index to load (press Enter to use '$EXCEL_SHEET'): " sheet_input
    if [[ -n "$sheet_input" ]]; then
      EXCEL_SHEET="$sheet_input"
    fi
  fi
fi

make_load_prelude() {
  if [[ "$EXT_LOWER" == "xlsx" ]]; then
    if [[ -n "$EXCEL_SHEET" ]]; then
      if [[ "$EXCEL_SHEET" =~ ^[0-9]+$ ]]; then
        SHEET_CLAUSE=", sheet = $EXCEL_SHEET"
      else
        SHEET_CLAUSE=", sheet = '$(sql_quote "$EXCEL_SHEET")'"
      fi
    else
      SHEET_CLAUSE=""
    fi
    cat <<SQL
PRAGMA disable_progress_bar;
SET threads TO 4;
INSTALL excel;
LOAD excel;
CREATE OR REPLACE VIEW v_all AS
SELECT *
FROM read_xlsx('$SRC_ESCAPED'${SHEET_CLAUSE}, header = true, ignore_errors = true);
SQL
  else
    cat <<SQL
PRAGMA disable_progress_bar;
SET threads TO 4;
CREATE OR REPLACE VIEW v_all AS
SELECT *
FROM read_csv_auto('$SRC_ESCAPED', header = true, sample_size = -1, nullstr = '');
SQL
  fi
}

# Metadata
echo "Loading dataset and showing metadata..."
duckdb <<SQL
$(make_load_prelude)
SELECT COUNT(*) AS total_rows FROM v_all;
PRAGMA table_info('v_all');
SELECT * FROM v_all LIMIT 1 OFFSET 1;
SELECT * FROM v_all
ORDER BY TRY_CAST("$COL_SALE_DATE" AS DATE) DESC NULLS LAST
LIMIT 1;
.quit
SQL

echo "Data loaded. Choose an option or LLM prompt."

while true; do
  echo
  echo "Menu:"
  echo "  1) Recent Office Sales & PPSF by Zip/City"
  echo "  2) Top Owners & Portfolios"
  echo "  3) Older Inventory & Value-Add Opportunities"
  echo "  4) Out-of-Area Owners"
  echo "  5) Size Distribution"
  echo "  6) Underperforming Assets"
  echo "  7) Transaction Volume / Hotspots"
  echo "  8) Value Drivers (YearBuilt, Size, etc.)"
  echo "  9) Long-Term Ownership"
  echo " 10) Test Parse of Website (FL DFS)"
  echo "  L) LLM Prompt / Analysis"
  echo "  0) Quit"
  read -p "Enter choice [0-9, L]: " choice

  case "$choice" in
    0)
      echo "Exiting."
      break
      ;;
    L|l)
      echo "--- LLM Analysis Prompt ---"
      read -p "Enter your prompt: " user_prompt
      if [[ -z "$user_prompt" ]]; then
        echo "No prompt entered."
        continue
      fi

      instruction="You are an expert DuckDB SQL generator. Convert the user's natural language request into a single DuckDB SQL query that can be executed against a view named v_all. Return only the SQL query without commentary or markdown."

      json_body=$(jq -n \
        --arg inst "$instruction" \
        --arg req "$user_prompt" \
        '{contents:[{parts:[{text:($inst + "\n\nRequest:\n" + $req)}]}]}')

      echo "=== Will send to LLM ==="
      echo "API Key: $GEMINI_API_KEY"
      echo "Endpoint: $GEMINI_ENDPOINT"
      echo "Prompt JSON body:"
      echo "$json_body"
      echo "========================"

      echo "Sending prompt to LLM..."
      # Use curl with x-goog-api-key header (per docs) or in URL? Use header style
      response_and_status=$(curl -s -w "\n%{http_code}" \
        -X POST "$GEMINI_ENDPOINT" \
        -H "Content-Type: application/json" \
        -H "x-goog-api-key: $GEMINI_API_KEY" \
        -d "$json_body"
      )
      http_status=$(echo "$response_and_status" | tail -n1)
      response_body=$(echo "$response_and_status" | sed '$d')

      if [[ "$http_status" != "200" ]]; then
        echo "ERROR: LLM API returned status $http_status"
        echo "Response body:"
        echo "$response_body"
        echo "Logging error..."
        echo "=== LLM Prompt Error ===" >> "$ANALYSIS_LOG"
        echo "Prompt: $user_prompt" >> "$ANALYSIS_LOG"
        echo "HTTP status: $http_status" >> "$ANALYSIS_LOG"
        echo "Body: $response_body" >> "$ANALYSIS_LOG"
      else
        generated=$(echo "$response_body" | jq -r '.candidates[0].content.parts[0].text // .candidates[0].content // .candidates[0].text // .result')
        sql_query=$(printf "%s\n" "$generated" | sed -e 's/^```[a-zA-Z]*$//' -e 's/^```$//' -e 's/```$//' )
        sql_query=$(printf "%s\n" "$sql_query" | sed '/^[[:space:]]*$/d')

        if [[ -z "$sql_query" ]]; then
          echo "No SQL query returned by LLM."
          echo "=== LLM Prompt Error ===" >> "$ANALYSIS_LOG"
          echo "Prompt: $user_prompt" >> "$ANALYSIS_LOG"
          echo "Body: $response_body" >> "$ANALYSIS_LOG"
          continue
        fi

        if [[ "$sql_query" != *';' ]]; then
          sql_query+=";"
        fi

        echo "LLM generated SQL:"
        echo "--------------------------------------------------"
        echo "$sql_query"
        echo "--------------------------------------------------"

        output_file="$(make_output_file L)"
        {
          echo "Prompt: $user_prompt"
          echo
          echo "Generated SQL:"
          echo "$sql_query"
          echo
          echo "Results:"
        } > "$output_file"

        duckdb <<SQL | tee -a "$output_file"
$(make_load_prelude)
.headers on
.mode box
$sql_query
.quit
SQL

        echo "Result: $output_file"
        {
          echo "=== LLM Prompt ==="
          echo "$user_prompt"
          echo "=== LLM SQL ==="
          echo "$sql_query"
          echo "=== LLM Output File ==="
          echo "$output_file"
        } >> "$ANALYSIS_LOG"
      fi
      ;;
    1)
      echo "--- Recent Office Sales & PPSF by Zip/City ---"
      output_file="$(make_output_file 1)"
      duckdb <<SQL | tee "$output_file"
$(make_load_prelude)
.headers on
.mode box
WITH base AS (
  SELECT
    "$COL_CITY" AS city,
    "$COL_ZIP" AS zip,
    TRY_CAST("$COL_SALE_DATE" AS DATE) AS sale_dt,
    TRY_CAST(
      REPLACE(
        REPLACE(CAST("$COL_SALE_AMOUNT" AS VARCHAR), ',', ''),
        '$', ''
      ) AS DOUBLE
    ) AS sale_amt,
    TRY_CAST(
      REPLACE(CAST("$COL_GROSS_AREA" AS VARCHAR), ',', '')
      AS DOUBLE
    ) AS gross_sf,
    CASE WHEN gross_sf > 0 THEN sale_amt / gross_sf END AS ppsf
  FROM v_all
  WHERE sale_dt >= date_trunc('day', now()) - INTERVAL '24 months'
    AND sale_amt IS NOT NULL
    AND gross_sf IS NOT NULL AND gross_sf > 0
)
SELECT
  COALESCE(zip, 'UNKNOWN') AS zip,
  COALESCE(city, 'UNKNOWN') AS city,
  COUNT(*) AS sale_count,
  ROUND(AVG(ppsf)::DOUBLE, 2) AS avg_ppsf,
  ROUND(quantile_cont(ppsf, 0.5), 2) AS median_ppsf,
  MIN(sale_dt) AS first_sale,
  MAX(sale_dt) AS last_sale
FROM base
GROUP BY zip, city
ORDER BY sale_count DESC;
.quit
SQL
      echo "Result: $output_file"
      ;;
    2)
      echo "--- Top Owners & Portfolios ---"
      output_file="$(make_output_file 2)"
      duckdb <<SQL | tee "$output_file"
$(make_load_prelude)
.headers on
.mode box
WITH inv AS (
  SELECT
    "$COL_OWNER" AS owner,
    TRY_CAST(
      REPLACE(
        REPLACE(CAST("$COL_GROSS_AREA" AS VARCHAR), ',', ''),
        '$', ''
      ) AS DOUBLE
    ) AS gross_sf
  FROM v_all
  WHERE "$COL_OWNER" IS NOT NULL
),
agg AS (
  SELECT
    owner,
    COUNT(*) AS property_count,
    ROUND(SUM(COALESCE(gross_sf, 0))::DOUBLE, 0) AS total_sf
  FROM inv
  GROUP BY owner
)
SELECT owner, property_count, total_sf
FROM agg
ORDER BY property_count DESC, total_sf DESC;
.quit
SQL
      echo "Result: $output_file"
      ;;
    3)
      echo "--- Older Inventory & Value-Add Opportunities ---"
      output_file="$(make_output_file 3)"
      duckdb <<SQL | tee "$output_file"
$(make_load_prelude)
.headers on
.mode box
WITH office AS (
  SELECT
    "$COL_CITY" AS city,
    "$COL_ZIP" AS zip,
    "$COL_YEAR_BUILT" AS year_built,
    TRY_CAST(
      REPLACE(
        REPLACE(CAST("$COL_BUILDING_VALUE" AS VARCHAR), ',', ''),
        '$', ''
      ) AS DOUBLE
    ) AS bldg_val,
    TRY_CAST(
      REPLACE(CAST("$COL_GROSS_AREA" AS VARCHAR), ',', '')
      AS DOUBLE
    ) AS gross_sf
  FROM v_all
),
buckets AS (
  SELECT *,
    CASE
      WHEN year_built IS NULL THEN 'Unknown'
      WHEN year_built < 1980 THEN 'Pre-1980'
      WHEN year_built < 2000 THEN '1980-1999'
      WHEN year_built < 2010 THEN '2000-2009'
      WHEN year_built < 2020 THEN '2010-2019'
      ELSE '2020+'
    END AS era,
    CASE WHEN gross_sf > 0 THEN bldg_val / gross_sf END AS bldg_val_psf
  FROM office
),
bench AS (
  SELECT zip, era,
    quantile_cont(bldg_val_psf, 0.25) AS p25_psf
  FROM buckets
  WHERE bldg_val_psf IS NOT NULL
  GROUP BY zip, era
),
scored AS (
  SELECT b.*, be.p25_psf,
    CASE WHEN b.bldg_val_psf IS NOT NULL AND bldg_val_psf < be.p25_psf THEN 1 ELSE 0 END AS is_low
  FROM buckets b
  LEFT JOIN bench be ON b.zip = be.zip AND b.era = be.era
)
SELECT
  COALESCE(zip, 'UNKNOWN') AS zip,
  era,
  COUNT(*) AS prop_count,
  SUM(is_low) AS low_count,
  ROUND(AVG(bldg_val_psf)::DOUBLE, 2) AS avg_psf,
  ROUND(AVG(p25_psf)::DOUBLE, 2) AS bench_p25
FROM scored
GROUP BY zip, era
HAVING SUM(is_low) > 0
ORDER BY low_count DESC;
.quit
SQL
      echo "Result: $output_file"
      ;;
    4)
      echo "--- Out-of-Area Owners ---"
      output_file="$(make_output_file 4)"
      duckdb <<SQL | tee "$output_file"
$(make_load_prelude)
.headers on
.mode box
WITH own AS (
  SELECT
    "$COL_OWNER" AS owner,
    OwnerState AS owner_state,
    OwnerZip AS owner_zip,
    "$COL_ZIP" AS prop_zip
  FROM v_all
)
SELECT owner, owner_state, owner_zip,
       COUNT(*) AS count_props,
       LIST(DISTINCT prop_zip) AS prop_zips
FROM own
WHERE owner IS NOT NULL
GROUP BY owner, owner_state, owner_zip
ORDER BY count_props DESC;
.quit
SQL
      echo "Result: $output_file"
      ;;
    5)
      echo "--- Size Distribution ---"
      output_file="$(make_output_file 5)"
      duckdb <<SQL | tee "$output_file"
$(make_load_prelude)
.headers on
.mode box
WITH ofc AS (
  SELECT
    TRY_CAST(
      REPLACE(CAST("$COL_GROSS_AREA" AS VARCHAR), ',', '')
      AS DOUBLE
    ) AS gross_sf
  FROM v_all
),
bins AS (
  SELECT
    CASE
      WHEN gross_sf < 5000 THEN 'Under 5,000'
      WHEN gross_sf < 15000 THEN '5,000–14,999'
      WHEN gross_sf < 50000 THEN '15,000–49,999'
      ELSE '50,000+'
    END AS size_bucket
  FROM ofc
  WHERE gross_sf IS NOT NULL
)
SELECT size_bucket,
       COUNT(*) AS props,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct
FROM bins
GROUP BY size_bucket
ORDER BY
  CASE size_bucket
    WHEN 'Under 5,000' THEN 1
    WHEN '5,000–14,999' THEN 2
    WHEN '15,000–49,999' THEN 3
    ELSE 4
  END;
.quit
SQL
      echo "Result: $output_file"
      ;;
    6)
      echo "--- Underperforming Assets ---"
      output_file="$(make_output_file 6)"
      duckdb <<SQL | tee "$output_file"
$(make_load_prelude)
.headers on
.mode box
WITH ofc AS (
  SELECT
    "$COL_CITY" AS city,
    "$COL_ZIP" AS zip,
    "$COL_YEAR_BUILT" AS year_built,
    TRY_CAST(
      REPLACE(
        REPLACE(CAST("$COL_BUILDING_VALUE" AS VARCHAR), ',', ''),
        '$', ''
      ) AS DOUBLE
    ) / NULLIF(
      TRY_CAST(
        REPLACE(CAST("$COL_GROSS_AREA" AS VARCHAR), ',', '')
        AS DOUBLE
      ), 0
    ) AS bldg_psf
  FROM v_all
  WHERE "$COL_GROSS_AREA" IS NOT NULL AND "$COL_BUILDING_VALUE" IS NOT NULL
),
bench AS (
  SELECT zip,
    quantile_cont(bldg_psf, 0.25) AS p25
  FROM ofc
  WHERE bldg_psf IS NOT NULL
  GROUP BY zip
)
SELECT o.city, o.zip, o.year_built, o.bldg_psf, b.p25 AS bench_p25
FROM ofc o
JOIN bench b USING(zip)
WHERE o.bldg_psf < b.p25
ORDER BY zip, o.bldg_psf;
.quit
SQL
      echo "Result: $output_file"
      ;;
    7)
      echo "--- Transaction Volume / Hotspots ---"
      output_file="$(make_output_file 7)"
      duckdb <<SQL | tee "$output_file"
$(make_load_prelude)
.headers on
.mode box
WITH sales AS (
  SELECT
    "$COL_CITY" AS city,
    "$COL_ZIP" AS zip,
    TRY_CAST("$COL_SALE_DATE" AS DATE) AS sale_dt
  FROM v_all
  WHERE sale_dt >= (now() - INTERVAL '36 months')
)
SELECT
  COALESCE(zip, 'UNKNOWN') AS zip,
  COALESCE(city, 'UNKNOWN') AS city,
  DATE_TRUNC('year', sale_dt) AS year,
  COUNT(*) AS num_sales
FROM sales
GROUP BY zip, city, year
ORDER BY year DESC, num_sales DESC;
.quit
SQL
      echo "Result: $output_file"
      ;;
    8)
      echo "--- Value Drivers (YearBuilt, Size, etc.) ---"
      output_file="$(make_output_file 8)"
      duckdb <<SQL | tee "$output_file"
$(make_load_prelude)
.headers on
.mode box
WITH sales AS (
  SELECT
    TRY_CAST("$COL_YEAR_BUILT" AS DOUBLE) AS yb,
    TRY_CAST(
      REPLACE(
        REPLACE(CAST("$COL_SALE_AMOUNT" AS VARCHAR), ',', ''),
        '$', ''
      ) AS DOUBLE
    ) / NULLIF(
      TRY_CAST(
        REPLACE(CAST("$COL_GROSS_AREA" AS VARCHAR), ',', '')
        AS DOUBLE
      ), 0
    ) AS ppsf
  FROM v_all
  WHERE ppsf IS NOT NULL
  ),
  corr AS (
    SELECT
      round(corr(yb, ppsf)::DOUBLE, 4) AS corr_year_ppsf
    FROM sales
  ),
  decades AS (
    SELECT
      CONCAT(CAST(FLOOR(yb/10)*10 AS VARCHAR), 's') AS decade,
      ppsf
    FROM sales
  ),
  med AS (
    SELECT
      CONCAT('median_ppsf_', decade) AS metric,
      round(quantile_cont(ppsf, 0.5), 2) AS value
    FROM decades
    GROUP BY decade
  )
SELECT
  'corr_year_ppsf' AS metric,
  corr_year_ppsf AS value
FROM corr
UNION ALL
SELECT metric, value FROM med;
.quit
SQL
      echo "Result: $output_file"
      ;;
    9)
      echo "--- Long-Term Ownership ---"
      output_file="$(make_output_file 9)"
      duckdb <<SQL | tee "$output_file"
$(make_load_prelude)
.headers on
.mode box
WITH inv AS (
  SELECT
    "$COL_OWNER" AS owner,
    TRY_CAST("$COL_SALE_DATE" AS DATE) AS sale_dt
  FROM v_all
),
agg AS (
  SELECT
    owner,
    COUNT(*) AS count_props,
    SUM(CASE WHEN sale_dt IS NULL OR sale_dt < (now() - INTERVAL '10 years') THEN 1 ELSE 0 END) AS long_hold_count
  FROM inv
  WHERE owner IS NOT NULL
  GROUP BY owner
)
SELECT owner, count_props, long_hold_count
FROM agg
WHERE long_hold_count > 0
ORDER BY long_hold_count DESC;
.quit
SQL
      echo "Result: $output_file"
      ;;
    10)
      echo "--- Test Parse of Website (Florida DFS) ---"
      if ! command -v python3 >/dev/null 2>&1; then
        echo "ERROR: python3 is required for the website parser."
        continue
      fi

      missing_modules=()
      for module in requests bs4 lxml; do
        if ! python3 -c "import importlib, sys; importlib.import_module(sys.argv[1])" "$module" >/dev/null 2>&1; then
          missing_modules+=("$module")
        fi
      done

      if (( ${#missing_modules[@]} > 0 )); then
        echo "ERROR: Missing Python modules: ${missing_modules[*]}"
        echo "Install them with: python3 -m pip install ${missing_modules[*]}"
        continue
      fi

      read -r -p "Enter entity name to search on the DFS site: " dfs_entity
      if [[ -z "$dfs_entity" ]]; then
        echo "No entity name entered."
        continue
      fi

      output_file="$(make_output_file 10)"
      python3 "$SCRIPT_DIR/scripts/fldfs_scraper.py" --entity "$dfs_entity" \
        | tee "$output_file"
      echo "Result: $output_file"
      ;;
    *)
      echo "Invalid choice: $choice"
      ;;
  esac
done

echo "Done. All output in $OUTDIR"
