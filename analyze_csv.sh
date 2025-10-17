#!/usr/bin/env bash
# analyze_office_menu_with_llm_show_prompt.sh
# Version: adds display of prompt and API key when using LLM menu option

# -- created by Martin Wolfe

set -euo pipefail
IFS=$'\n'

if command -v clear >/dev/null 2>&1; then
  clear
else
  printf '\033c'
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOGFILE="$SCRIPT_DIR/script-run.log"
ANALYSIS_LOG="$SCRIPT_DIR/analysis-results.log"
OUTDIR="$SCRIPT_DIR/output"

LOCAL_DB_PATH="$SCRIPT_DIR/local.duckdb"
LOCAL_TABLE_NAME="source_dataset"

PKG_INSTALL_CMD=""

detect_package_manager() {
  if command -v brew >/dev/null 2>&1; then
    PKG_INSTALL_CMD="brew install"
  elif command -v apt-get >/dev/null 2>&1; then
    PKG_INSTALL_CMD="sudo apt-get install"
  elif command -v apt >/dev/null 2>&1; then
    PKG_INSTALL_CMD="sudo apt install"
  elif command -v dnf >/dev/null 2>&1; then
    PKG_INSTALL_CMD="sudo dnf install"
  elif command -v pacman >/dev/null 2>&1; then
    PKG_INSTALL_CMD="sudo pacman -S"
  elif command -v zypper >/dev/null 2>&1; then
    PKG_INSTALL_CMD="sudo zypper install"
  fi
}

install_hint() {
  local package_name="$1"
  if [[ -n "$PKG_INSTALL_CMD" ]]; then
    printf 'Install via: %s %s\n' "$PKG_INSTALL_CMD" "$package_name"
  else
    printf 'Please install "%s" using your system package manager.\n' "$package_name"
  fi
}

check_dependency() {
  local binary_name="$1"
  printf 'Checking dependency: %s... ' "$binary_name"
  if command -v "$binary_name" >/dev/null 2>&1; then
    printf 'found.\n'
  else
    printf 'missing!\n'
    install_hint "$binary_name"
    exit 1
  fi
}

print_title_box() {
  local reset='\033[0m'
  local border_color='\033[1;34m'
  local title_color='\033[1;97m'
  local accent_color='\033[1;36m'
  local border_line="+========================================================================+"

  printf '%b%s%b\n' "$border_color" "$border_line" "$reset"
  printf '%b| %b%-70s%b %b|\n' "$border_color" "$title_color" "Dataset Parsing Toolkit" "$reset" "$border_color"
  printf '%b| %b%-70s%b %b|\n' "$border_color" "$accent_color" "industryzoom.ai" "$reset" "$border_color"
  printf '%b| %b%-70s%b %b|\n' "$border_color" "$title_color" "(c) 2025 industryzoom.ai. All rights reserved." "$reset" "$border_color"
  printf '%b%s%b\n' "$border_color" "$border_line" "$reset"
  echo
  printf 'Session started: %s\n' "$(date)"
  printf 'Run log: %s\n' "$LOGFILE"
  printf 'Analysis log: %s\n' "$ANALYSIS_LOG"
  echo
}

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

print_title_box

detect_package_manager

echo "Dependency check results:"
check_dependency duckdb
check_dependency jq
check_dependency curl
echo

DEFAULT_INPUT="${1:-}"

if [[ -n "$DEFAULT_INPUT" ]]; then
  if [[ "$DEFAULT_INPUT" == /* ]]; then
    SRC="$DEFAULT_INPUT"
  else
    SRC="$SCRIPT_DIR/$DEFAULT_INPUT"
  fi
  if [[ ! -f "$SRC" ]]; then
    echo "ERROR: Provided dataset file not found: $DEFAULT_INPUT"
    exit 1
  fi
  SRC_BASENAME="$(basename "$SRC")"
else
  DATASET_FILES=()
  while IFS= read -r dataset_file; do
    DATASET_FILES+=("$dataset_file")
  done < <({
    find "$SCRIPT_DIR" -type f -iname '*.csv'
    find "$SCRIPT_DIR" -type f -iname '*.xlsx'
    find "$SCRIPT_DIR" -type f -iname '*.xls'
    find "$SCRIPT_DIR" -type f -iname '*.txt'
  } | sort -u)

  if (( ${#DATASET_FILES[@]} == 0 )); then
    echo "ERROR: No dataset files (.csv, .xlsx, .xls, .txt) found in $SCRIPT_DIR"
    exit 1
  fi

  while true; do
    echo "Available dataset files:"
    for idx in "${!DATASET_FILES[@]}"; do
      display_name="${DATASET_FILES[$idx]#"$SCRIPT_DIR"/}"
      printf '  %2d) %s\n' "$((idx + 1))" "${display_name:-$(basename "${DATASET_FILES[$idx]}")}"
    done
    read -r -p "Select dataset file [1-${#DATASET_FILES[@]}]: " selection

    if [[ "$selection" =~ ^[0-9]+$ ]]; then
      selection=$((selection))
      if (( selection >= 1 && selection <= ${#DATASET_FILES[@]} )); then
        SRC="${DATASET_FILES[selection-1]}"
        SRC_BASENAME="$(basename "$SRC")"
        break
      fi
    fi
    echo "Invalid selection. Please choose a number between 1 and ${#DATASET_FILES[@]}."
  done
fi

EXCEL_SHEET="${2:-}"

mkdir -p "$OUTDIR"

make_output_file() {
  local menu_choice="$1"
  local timestamp
  timestamp="$(date +%Y%m%d-%H%M%S)"
  printf "%s/menu-item_%s_%s.log" "$OUTDIR" "$menu_choice" "$timestamp"
}

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

load_dataset_into_local_db() {
  echo "Preparing local DuckDB database at $LOCAL_DB_PATH..."
  duckdb "$LOCAL_DB_PATH" <<SQL
$(make_load_prelude)
CREATE OR REPLACE TABLE "$LOCAL_TABLE_NAME" AS SELECT * FROM v_all;
DROP VIEW IF EXISTS v_all;
CREATE OR REPLACE VIEW v_all AS SELECT * FROM "$LOCAL_TABLE_NAME";
.quit
SQL
  echo "Local DuckDB database ready."
}

load_dataset_into_local_db

# Metadata
echo "Loading dataset and showing metadata..."
TOTAL_ROWS=$(duckdb "$LOCAL_DB_PATH" <<'SQL'
.headers off
.mode list
SELECT COUNT(*) FROM v_all;
.quit
SQL
)
TOTAL_COLUMNS=$(duckdb "$LOCAL_DB_PATH" <<'SQL'
.headers off
.mode list
SELECT COUNT(*) FROM pragma_table_info('v_all');
.quit
SQL
)

echo "Dataset dimensions: ${TOTAL_ROWS} rows × ${TOTAL_COLUMNS} columns"
echo
echo "Column overview:"
duckdb "$LOCAL_DB_PATH" <<'SQL'
.headers on
.mode column
SELECT cid AS column_index,
       name AS column_name,
       type AS column_type
FROM pragma_table_info('v_all')
ORDER BY cid;
.quit
SQL
echo

COLUMN_METADATA_TEXT="$(duckdb "$LOCAL_DB_PATH" <<'SQL'
.mode csv
.headers off
SELECT name || ' (' || type || ')' FROM pragma_table_info('v_all') ORDER BY cid;
.quit
SQL
)"
COLUMN_METADATA_TEXT="$(echo "$COLUMN_METADATA_TEXT" | sed '/^$/d')"

echo "Data loaded. Choose an option or LLM prompt."

while true; do
  echo
  echo "Menu:"
  echo "  1) Source dataset – row/column counts"
  echo "  2) Local DuckDB – row/column counts"
  echo "  3) Source dataset – column details"
  echo "  4) Local DuckDB – column details"
  echo "  5) Source dataset – first row (vertical view)"
  echo "  6) Open DuckDB UI"
  echo "  L) LLM Prompt and Analysis"
  echo "  0) Quit"
  read -r -p "Enter choice [0-6, L]: " choice

  case "$choice" in
    0)
      echo "Exiting."
      break
      ;;
    L|l)
      echo "--- LLM Prompt and Analysis ---"
      read -r -p "Enter your prompt: " user_prompt
      if [[ -z "$user_prompt" ]]; then
        echo "No prompt entered."
        continue
      fi

      output_file="$(make_output_file L)"
      prompt_context="$user_prompt"
      clarification_history=()

      while true; do
        instruction=$(cat <<'INSTRUCTION'
You are an expert DuckDB SQL assistant. Generate DuckDB-compatible SQL that queries the view v_all in the local database. Use only the provided column names exactly as written. If the user request lacks details required to form a valid SQL query, ask a clarifying question. Always reply with compact JSON using this schema: {"needs_clarification": <true|false>, "clarifying_question": "...", "sql": "..."}. When providing SQL include a terminating semicolon and no additional commentary.
INSTRUCTION
)
        columns_text=$'Available columns (name and inferred type):\n'"$COLUMN_METADATA_TEXT"
        request_text=$'User request and clarifications:\n'"$prompt_context"
        json_body=$(jq -n \
          --arg inst "$instruction" \
          --arg cols "$columns_text" \
          --arg req "$request_text" \
          '{contents:[{parts:[{text:($inst + "\n\n" + $cols + "\n\n" + $req)}]}]}' )

        echo "=== Will send to LLM ==="
        echo "API Key: $GEMINI_API_KEY"
        echo "Endpoint: $GEMINI_ENDPOINT"
        echo "Prompt JSON body:"
        echo "$json_body"
        echo "========================"

        echo "Sending prompt to LLM..."
        response_and_status=$(curl -s -w "\n%{http_code}" \
          -X POST "$GEMINI_ENDPOINT" \
          -H "Content-Type: application/json" \
          -H "x-goog-api-key: $GEMINI_API_KEY" \
          -d "$json_body" )
        http_status=$(echo "$response_and_status" | tail -n1)
        response_body=$(echo "$response_and_status" | sed '$d')

        if [[ "$http_status" != "200" ]]; then
          echo "ERROR: LLM API returned status $http_status"
          echo "Response body:"
          echo "$response_body"
          echo "Logging error..."
          {
            echo "=== LLM Prompt Error ==="
            echo "Prompt: $prompt_context"
            echo "HTTP status: $http_status"
            echo "Body: $response_body"
          } >> "$ANALYSIS_LOG"
          break
        fi

        generated=$(echo "$response_body" | jq -r '.candidates[0].content.parts[0].text // .candidates[0].content // .candidates[0].text // .result')
        if [[ -z "$generated" ]]; then
          echo "ERROR: LLM response did not include text content."
          {
            echo "=== LLM Prompt Error ==="
            echo "Prompt: $prompt_context"
            echo "Body: $response_body"
          } >> "$ANALYSIS_LOG"
          break
        fi

        if ! echo "$generated" | jq empty >/dev/null 2>&1; then
          echo "ERROR: LLM response was not valid JSON."
          echo "$generated"
          {
            echo "=== LLM Prompt Error ==="
            echo "Prompt: $prompt_context"
            echo "Body: $generated"
          } >> "$ANALYSIS_LOG"
          break
        fi

        needs_clarification=$(echo "$generated" | jq -r '.needs_clarification // false')
        if [[ "$needs_clarification" == "true" ]]; then
          clarifying_question=$(echo "$generated" | jq -r '.clarifying_question // ""')
          if [[ -z "$clarifying_question" ]]; then
            echo "ERROR: Clarification requested but no question provided."
            break
          fi
          echo "Clarification needed: $clarifying_question"
          read -r -p "Your answer: " clarification_answer
          if [[ -z "$clarification_answer" ]]; then
            echo "No clarification provided. Cancelling LLM workflow."
            break
          fi
          clarification_history+=("Q: $clarifying_question" "A: $clarification_answer")
          prompt_context+=$'\nQ: '"$clarifying_question"$'\nA: '"$clarification_answer"
          continue
        fi

        sql_query=$(echo "$generated" | jq -r '.sql // ""')
        if [[ -z "$sql_query" ]]; then
          echo "ERROR: LLM did not return SQL."
          {
            echo "=== LLM Prompt Error ==="
            echo "Prompt: $prompt_context"
            echo "Body: $generated"
          } >> "$ANALYSIS_LOG"
          break
        fi

        if [[ "$sql_query" != *';' ]]; then
          sql_query+=";"
        fi

        echo "LLM generated SQL:"
        echo "--------------------------------------------------"
        echo "$sql_query"
        echo "--------------------------------------------------"

        {
          echo "Prompt: $user_prompt"
          if (( ${#clarification_history[@]} > 0 )); then
            echo
            echo "Clarifications:"
            printf '%s\n' "${clarification_history[@]}"
          fi
          echo
          echo "Generated SQL:"
          echo "$sql_query"
          echo
          echo "Results:"
        } > "$output_file"

        duckdb "$LOCAL_DB_PATH" <<SQL | tee -a "$output_file"
.headers on
.mode box
$sql_query
.quit
SQL

        echo "Result: $output_file"
        {
          echo "=== LLM Prompt ==="
          echo "$user_prompt"
          if (( ${#clarification_history[@]} > 0 )); then
            echo "=== Clarifications ==="
            printf '%s\n' "${clarification_history[@]}"
          fi
          echo "=== LLM SQL ==="
          echo "$sql_query"
          echo "=== LLM Output File ==="
          echo "$output_file"
        } >> "$ANALYSIS_LOG"
        break
      done
      ;;
    1)
      echo "--- Source dataset – row/column counts ---"
      output_file="$(make_output_file 1)"
      duckdb <<SQL | tee "$output_file"
$(make_load_prelude)
.headers on
.mode box
SELECT
  'Source Dataset' AS dataset,
  (SELECT COUNT(*) FROM v_all) AS total_rows,
  (SELECT COUNT(*) FROM pragma_table_info('v_all')) AS total_columns;
.quit
SQL
      echo "Result: $output_file"
      ;;
    2)
      echo "--- Local DuckDB – row/column counts ---"
      output_file="$(make_output_file 2)"
      duckdb "$LOCAL_DB_PATH" <<SQL | tee "$output_file"
.headers on
.mode box
SELECT
  'Local DuckDB' AS dataset,
  (SELECT COUNT(*) FROM $LOCAL_TABLE_NAME) AS total_rows,
  (SELECT COUNT(*) FROM pragma_table_info('$LOCAL_TABLE_NAME')) AS total_columns;
.quit
SQL
      echo "Result: $output_file"
      ;;
    3)
      echo "--- Source dataset – column details ---"
      output_file="$(make_output_file 3)"
      duckdb <<SQL | tee "$output_file"
$(make_load_prelude)
.headers on
.mode box
SELECT
  cid AS ordinal_position,
  name AS column_name,
  type AS data_type,
  TRY_CAST(NULLIF(REGEXP_EXTRACT(type, '\\((\\d+)\\)'), '') AS INTEGER) AS length,
  CASE WHEN "notnull" THEN 'NO' ELSE 'YES' END AS is_nullable,
  COALESCE(CAST(dflt_value AS VARCHAR), 'NULL') AS default_value
FROM pragma_table_info('v_all')
ORDER BY cid;
.quit
SQL
      echo "Result: $output_file"
      ;;
    4)
      echo "--- Local DuckDB – column details ---"
      output_file="$(make_output_file 4)"
      duckdb "$LOCAL_DB_PATH" <<SQL | tee "$output_file"
.headers on
.mode box
SELECT
  cid AS ordinal_position,
  name AS column_name,
  type AS data_type,
  TRY_CAST(NULLIF(REGEXP_EXTRACT(type, '\\((\\d+)\\)'), '') AS INTEGER) AS length,
  CASE WHEN "notnull" THEN 'NO' ELSE 'YES' END AS is_nullable,
  COALESCE(CAST(dflt_value AS VARCHAR), 'NULL') AS default_value
FROM pragma_table_info('$LOCAL_TABLE_NAME')
ORDER BY cid;
.quit
SQL
      echo "Result: $output_file"
      ;;
    5)
      echo "--- Source dataset – first row (vertical view) ---"
      output_file="$(make_output_file 5)"
      duckdb <<SQL | tee "$output_file"
$(make_load_prelude)
.headers on
.mode box
WITH first_row AS (
  SELECT * FROM v_all LIMIT 1
),
json_row AS (
  SELECT to_json(first_row) AS row_json FROM first_row
),
column_info AS (
  SELECT cid, name FROM pragma_table_info('v_all') ORDER BY cid
),
kv_pairs AS (
  SELECT key, value
  FROM json_row, json_each(json_row.row_json)
)
SELECT
  column_info.name AS column_name,
  CASE
    WHEN json_row.row_json IS NULL THEN '<<no rows available>>'
    ELSE COALESCE(CAST(kv_pairs.value AS VARCHAR), 'NULL')
  END AS value
FROM column_info
LEFT JOIN json_row ON TRUE
LEFT JOIN kv_pairs ON kv_pairs.key = column_info.name;
.quit
SQL
      echo "Result: $output_file"
      ;;
    6)
      echo "--- Open DuckDB UI ---"
      duckdb -ui "$LOCAL_DB_PATH"
      ;;
    *)
      echo "Invalid choice: $choice"
      ;;
  esac
done

echo "Done. All output in $OUTDIR"
