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
MERGE_LOG="$SCRIPT_DIR/merge-summary.log"
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
  printf 'Merge summary log: %s\n' "$MERGE_LOG"
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

RESPONSE_SCHEMA=$(cat <<'JSON'
{
  "type": "object",
  "properties": {
    "needs_clarification": {"type": "boolean"},
    "clarifying_question": {"type": "string", "nullable": true},
    "sql": {"type": "string", "nullable": true}
  },
  "required": ["needs_clarification", "clarifying_question", "sql"]
}
JSON
)

# Function to log and also echo a message
note () { echo "$*" | tee -a "$ANALYSIS_LOG" >/dev/null; }
sql_quote() { printf "%s" "$1" | sed "s/'/''/g"; }

normalize_column_name() {
  local raw="$1"
  printf "%s" "$raw" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9'
}

log_merge() {
  local message="$1"
  printf "%s\n" "$message" | tee -a "$MERGE_LOG"
}

strip_code_fences() {
  python3 -c '
import sys

text = sys.stdin.read()
text = text.strip()

if text.startswith("```"):
    lines = text.splitlines()
    if lines and lines[0].lstrip().startswith("```"):
        lines = lines[1:]
    while lines and not lines[-1].strip():
        lines = lines[:-1]
    if lines and lines[-1].strip().startswith("```"):
        lines = lines[:-1]
    text = "\n".join(lines).strip()

sys.stdout.write(text)
'
}

exec > >(tee -a "$LOGFILE") 2>&1

print_title_box

detect_package_manager

echo "Dependency check results:"
check_dependency duckdb
check_dependency jq
check_dependency curl
check_dependency python3
echo

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

make_load_prelude() {
  local needs_excel=0
  local union_sql=""

  for file_path in "${SELECTED_FILES[@]}"; do
    local ext="${file_path##*.}"
    local ext_lower
    ext_lower="$(printf "%s" "$ext" | tr '[:upper:]' '[:lower:]')"
    local file_escaped
    file_escaped="$(sql_quote "$file_path")"
    local display_name
    display_name="${file_path#"$SCRIPT_DIR"/}"
    [[ -z "$display_name" ]] && display_name="$(basename "$file_path")"
    local display_name_escaped
    display_name_escaped="$(sql_quote "$display_name")"
    local select_stmt

    if [[ "$ext_lower" == "xlsx" || "$ext_lower" == "xls" ]]; then
      needs_excel=1
      local sheet_clause=""
      local sheet_value="${FILE_SHEETS[$file_path]-}"
      if [[ -n "$sheet_value" ]]; then
        if [[ "$sheet_value" =~ ^[0-9]+$ ]]; then
          sheet_clause=", sheet = $sheet_value"
        else
          sheet_clause=", sheet = '$(sql_quote "$sheet_value")'"
        fi
      fi
      select_stmt="SELECT *, '${display_name_escaped}' AS __source_file FROM read_xlsx('${file_escaped}'${sheet_clause}, header = true, ignore_errors = true)"
    else
      select_stmt="SELECT *, '${display_name_escaped}' AS __source_file FROM read_csv_auto('${file_escaped}', header = true, sample_size = -1, nullstr = '', all_varchar = true)"
    fi

    if [[ -z "$union_sql" ]]; then
      union_sql="  $select_stmt"
    else
      printf -v union_sql '%s\nUNION ALL BY NAME\n  %s' "$union_sql" "$select_stmt"
    fi
  done

  local excel_setup=""
  if (( needs_excel )); then
    excel_setup=$'INSTALL excel;\nLOAD excel;'
  fi

  cat <<SQL
PRAGMA disable_progress_bar;
SET threads TO 4;
$excel_setup
CREATE OR REPLACE VIEW v_all AS
WITH unioned AS (
$union_sql
)
SELECT * FROM unioned;
SQL
}

declare -a PROPERTY_LISTING_COLUMNS=(
  "ListingID|VARCHAR(50)"
  "County|VARCHAR(50)"
  "StateAbbrev|CHAR(2)"
  "ParcelId|VARCHAR(50)"
  "STRAP|VARCHAR(50)"
  "Folio|VARCHAR(50)"
  "FolioID|VARCHAR(50)"
  "SiteStreetAddress|VARCHAR(200)"
  "SiteStreetNumber|VARCHAR(50)"
  "SiteStreetName|VARCHAR(100)"
  "SiteStreetType|VARCHAR(50)"
  "SiteStreetOrdinal|VARCHAR(50)"
  "SiteUnit|VARCHAR(50)"
  "SiteCity|VARCHAR(100)"
  "SiteZipCode|VARCHAR(20)"
  "SubdivisionCondoNum|VARCHAR(50)"
  "MapNumber|VARCHAR(50)"
  "BlockBldg|VARCHAR(50)"
  "LotUnit|VARCHAR(50)"
  "Section|VARCHAR(50)"
  "Township|VARCHAR(50)"
  "Range|VARCHAR(50)"
  "TotalAcres|DECIMAL(18,6)"
  "TaxYear|INT"
  "RollType|VARCHAR(50)"
  "UseCode|VARCHAR(50)"
  "ClassCode|VARCHAR(50)"
  "StrapNumber|VARCHAR(50)"
  "OwnerLine1|VARCHAR(200)"
  "OwnerLine2|VARCHAR(200)"
  "OwnerLine3|VARCHAR(200)"
  "OwnerLine4|VARCHAR(200)"
  "OwnerLine5|VARCHAR(200)"
  "OwnerName|VARCHAR(200)"
  "OwnerCountry|VARCHAR(100)"
  "OwnerCity|VARCHAR(100)"
  "OwnerState|VARCHAR(50)"
  "OwnerZip|VARCHAR(20)"
  "OwnerZipPlus4|VARCHAR(10)"
  "OwnerForeignMailCode|VARCHAR(50)"
  "Others|VARCHAR(200)"
  "CareOf|VARCHAR(200)"
  "OwnerAddress1|VARCHAR(200)"
  "OwnerAddress2|VARCHAR(200)"
  "ImprovementCode|VARCHAR(50)"
  "ImprovementDescription|VARCHAR(200)"
  "DORCode|VARCHAR(50)"
  "DORDescription|VARCHAR(200)"
  "LegalDescription|TEXT"
  "JustValue|DECIMAL(18,2)"
  "LandJustValue|DECIMAL(18,2)"
  "ImprovementsJustValue|DECIMAL(18,2)"
  "TotalJustValue|DECIMAL(18,2)"
  "LandValue|DECIMAL(18,2)"
  "BuildingValue|DECIMAL(18,2)"
  "HeatedArea|DECIMAL(18,2)"
  "GrossArea|DECIMAL(18,2)"
  "TotalLivingArea|DECIMAL(18,2)"
  "LandArea|DECIMAL(18,2)"
  "Bathrooms|DECIMAL(5,2)"
  "YearBuilt|INT"
  "Pool|VARCHAR(50)"
  "ORNumber|VARCHAR(50)"
  "SaleDate|DATE"
  "SaleAmount|DECIMAL(18,2)"
  "SOHBenefit|DECIMAL(18,2)"
  "NonSchool10PctBenefit|DECIMAL(18,2)"
  "AgriculturalClassBenefit|DECIMAL(18,2)"
  "CountyAssessedValue|DECIMAL(18,2)"
  "SchoolAssessedValue|DECIMAL(18,2)"
  "MunicipalAssessedValue|DECIMAL(18,2)"
  "OtherAssessedValue|DECIMAL(18,2)"
  "HmstdExemptAmount|DECIMAL(18,2)"
  "NonSchoolAddHmstdExemptAmount|DECIMAL(18,2)"
  "CountySeniorExemptAmount|DECIMAL(18,2)"
  "MunicipalSeniorExemptAmount|DECIMAL(18,2)"
  "CountyLongTermSeniorExemptAmount|DECIMAL(18,2)"
  "DisabledExemptPct|DECIMAL(5,2)"
  "DisabledExemptCode|VARCHAR(50)"
  "DisabledExemptDesc|VARCHAR(200)"
  "DisabledExemptAmount|DECIMAL(18,2)"
  "CivExemptAmount|DECIMAL(18,2)"
  "VetExemptAmount|DECIMAL(18,2)"
  "WidowExemptAmount|DECIMAL(18,2)"
  "BlindExemptAmount|DECIMAL(18,2)"
  "WhollyExemptPct|DECIMAL(5,2)"
  "WhollyExemptCode|VARCHAR(50)"
  "WhollyExemptDesc|VARCHAR(200)"
  "NonSchoolWhollyExemptAmount|DECIMAL(18,2)"
  "SchoolWhollyExemptAmount|DECIMAL(18,2)"
  "DisableVetExemptPct|DECIMAL(5,2)"
  "CountyDisabledVetExemptAmount|DECIMAL(18,2)"
  "SchoolDisabledVetExemptAmount|DECIMAL(18,2)"
  "MunicipalDisabledVetExemptAmount|DECIMAL(18,2)"
  "OtherDisabledVetExemptAmount|DECIMAL(18,2)"
  "DeployedExemptPct|DECIMAL(5,2)"
  "CountyDeployedExemptAmount|DECIMAL(18,2)"
  "SchoolDeployedExemptAmount|DECIMAL(18,2)"
  "MunicipalDeployedExemptAmount|DECIMAL(18,2)"
  "OtherDeployedExemptAmount|DECIMAL(18,2)"
  "AfdHsgExemptPct|DECIMAL(5,2)"
  "CountyAfdHsgExemptAmount|DECIMAL(18,2)"
  "SchoolAfdHsgExemptAmount|DECIMAL(18,2)"
  "MunicipalAfdHsgExemptAmount|DECIMAL(18,2)"
  "OtherAfdHsgExemptAmount|DECIMAL(18,2)"
  "CountyTaxableValue|DECIMAL(18,2)"
  "SchoolTaxableValue|DECIMAL(18,2)"
  "MunicipalTaxableValue|DECIMAL(18,2)"
  "OtherTaxableValue|DECIMAL(18,2)"
  "MillageArea|VARCHAR(50)"
  "CountyMillage|DECIMAL(8,4)"
  "SchoolMillage|DECIMAL(8,4)"
  "MunicipalMillage|DECIMAL(8,4)"
  "OtherMillage|DECIMAL(8,4)"
  "CountyTaxes|DECIMAL(18,2)"
  "SchoolTaxes|DECIMAL(18,2)"
  "MunicipalTaxes|DECIMAL(18,2)"
  "OtherTaxes|DECIMAL(18,2)"
  "TotalAdvTaxes|DECIMAL(18,2)"
  "TotalNadvTaxes|DECIMAL(18,2)"
  "TotalTaxes|DECIMAL(18,2)"
  "GisFlnNum|VARCHAR(50)"
  "RowCheckSum|BIGINT"
  "CreatedAt|TIMESTAMP"
  "UpdatedAt|TIMESTAMP"
)

declare -A PROPERTY_LISTING_ALIAS_MAP=(
  [county]="countyname"
  [stateabbrev]="state|stateabbr|stateabbreviation|state_abbrev"
  [parcelid]="parcel|parcel_id|parcelnumber"
  [strap]="strapid|strap_id"
  [strapnumber]="strap|strapnum|strap_number"
  [sitestreetaddress]="situsaddress|address"
  [sitestreetnumber]="sitenumber|streetnumber"
  [sitestreetname]="streetname"
  [sitecity]="city|sitecityname"
  [sitezipcode]="sitezip|site_zip|sitezipcode|site_zipcode|zipcode|zip"
  [ownername]="owner|owner_full_name"
  [owneraddress1]="owneraddr1|owner_address1"
  [owneraddress2]="owneraddr2|owner_address2"
  [ownerzip]="ownerpostalcode|owner_zip"
  [ownerzipplus4]="ownerzip4|owner_zip_plus4"
  [justvalue]="marketvalue|just_value"
  [landjustvalue]="landmarketvalue"
  [improvementsjustvalue]="buildingjustvalue|improvementvalue"
  [landvalue]="landmarketvalue|land_cost"
  [buildingvalue]="buildingmarketvalue|improvementsvalue"
  [heatedarea]="heatedsqft|heated_area"
  [grossarea]="grosssqft|gross_area"
  [totallivingarea]="livingarea|total_living_area|heatedsqft"
  [landarea]="land_sqft|land_square_feet"
  [bathrooms]="baths|numberofbaths"
  [yearbuilt]="year_build|built_year"
  [pool]="poolflag|poolyn"
  [ornumber]="bookpage|orbookpage"
  [saledate]="salesdate|closingdate|dateofsale"
  [saleamount]="saleprice|salesprice|price"
  [millagearea]="millagedistrict"
  [gisflnnum]="gisid|gisnumber"
)

declare -a MERGE_MAPPED_FIELDS=()
declare -a MERGE_DEFAULTED_FIELDS=()

property_listing_create_sql() {
  cat <<'SQL'
CREATE TABLE PropertyListing (
    ListingID           VARCHAR(50)     PRIMARY KEY,
    County              VARCHAR(50)     NOT NULL,
    StateAbbrev         CHAR(2)         NOT NULL,
    ParcelId            VARCHAR(50),
    STRAP               VARCHAR(50),
    Folio               VARCHAR(50),
    FolioID             VARCHAR(50),
    SiteStreetAddress   VARCHAR(200),
    SiteStreetNumber    VARCHAR(50),
    SiteStreetName      VARCHAR(100),
    SiteStreetType      VARCHAR(50),
    SiteStreetOrdinal   VARCHAR(50),
    SiteUnit            VARCHAR(50),
    SiteCity            VARCHAR(100),
    SiteZipCode         VARCHAR(20),
    SubdivisionCondoNum VARCHAR(50),
    MapNumber           VARCHAR(50),
    BlockBldg           VARCHAR(50),
    LotUnit             VARCHAR(50),
    Section             VARCHAR(50),
    Township            VARCHAR(50),
    Range               VARCHAR(50),
    TotalAcres          DECIMAL(18,6),
    TaxYear             INT,
    RollType            VARCHAR(50),
    UseCode             VARCHAR(50),
    ClassCode           VARCHAR(50),
    StrapNumber         VARCHAR(50),
    OwnerLine1          VARCHAR(200),
    OwnerLine2          VARCHAR(200),
    OwnerLine3          VARCHAR(200),
    OwnerLine4          VARCHAR(200),
    OwnerLine5          VARCHAR(200),
    OwnerName           VARCHAR(200),
    OwnerCountry        VARCHAR(100),
    OwnerCity           VARCHAR(100),
    OwnerState          VARCHAR(50),
    OwnerZip            VARCHAR(20),
    OwnerZipPlus4       VARCHAR(10),
    OwnerForeignMailCode VARCHAR(50),
    Others              VARCHAR(200),
    CareOf              VARCHAR(200),
    OwnerAddress1       VARCHAR(200),
    OwnerAddress2       VARCHAR(200),
    ImprovementCode         VARCHAR(50),
    ImprovementDescription  VARCHAR(200),
    DORCode                 VARCHAR(50),
    DORDescription          VARCHAR(200),
    LegalDescription        TEXT,
    JustValue           DECIMAL(18,2),
    LandJustValue       DECIMAL(18,2),
    ImprovementsJustValue DECIMAL(18,2),
    TotalJustValue      DECIMAL(18,2),
    LandValue           DECIMAL(18,2),
    BuildingValue       DECIMAL(18,2),
    HeatedArea          DECIMAL(18,2),
    GrossArea           DECIMAL(18,2),
    TotalLivingArea     DECIMAL(18,2),
    LandArea            DECIMAL(18,2),
    Bathrooms           DECIMAL(5,2),
    YearBuilt           INT,
    Pool                VARCHAR(50),
    ORNumber            VARCHAR(50),
    SaleDate            DATE,
    SaleAmount          DECIMAL(18,2),
    SOHBenefit                 DECIMAL(18,2),
    NonSchool10PctBenefit       DECIMAL(18,2),
    AgriculturalClassBenefit    DECIMAL(18,2),
    CountyAssessedValue       DECIMAL(18,2),
    SchoolAssessedValue       DECIMAL(18,2),
    MunicipalAssessedValue    DECIMAL(18,2),
    OtherAssessedValue        DECIMAL(18,2),
    HmstdExemptAmount              DECIMAL(18,2),
    NonSchoolAddHmstdExemptAmount  DECIMAL(18,2),
    CountySeniorExemptAmount       DECIMAL(18,2),
    MunicipalSeniorExemptAmount    DECIMAL(18,2),
    CountyLongTermSeniorExemptAmount DECIMAL(18,2),
    DisabledExemptPct             DECIMAL(5,2),
    DisabledExemptCode            VARCHAR(50),
    DisabledExemptDesc            VARCHAR(200),
    DisabledExemptAmount           DECIMAL(18,2),
    CivExemptAmount                DECIMAL(18,2),
    VetExemptAmount                DECIMAL(18,2),
    WidowExemptAmount              DECIMAL(18,2),
    BlindExemptAmount              DECIMAL(18,2),
    WhollyExemptPct              DECIMAL(5,2),
    WhollyExemptCode             VARCHAR(50),
    WhollyExemptDesc             VARCHAR(200),
    NonSchoolWhollyExemptAmount   DECIMAL(18,2),
    SchoolWhollyExemptAmount      DECIMAL(18,2),
    DisableVetExemptPct            DECIMAL(5,2),
    CountyDisabledVetExemptAmount  DECIMAL(18,2),
    SchoolDisabledVetExemptAmount  DECIMAL(18,2),
    MunicipalDisabledVetExemptAmount DECIMAL(18,2),
    OtherDisabledVetExemptAmount    DECIMAL(18,2),
    DeployedExemptPct              DECIMAL(5,2),
    CountyDeployedExemptAmount      DECIMAL(18,2),
    SchoolDeployedExemptAmount      DECIMAL(18,2),
    MunicipalDeployedExemptAmount   DECIMAL(18,2),
    OtherDeployedExemptAmount       DECIMAL(18,2),
    AfdHsgExemptPct                 DECIMAL(5,2),
    CountyAfdHsgExemptAmount        DECIMAL(18,2),
    SchoolAfdHsgExemptAmount        DECIMAL(18,2),
    MunicipalAfdHsgExemptAmount     DECIMAL(18,2),
    OtherAfdHsgExemptAmount         DECIMAL(18,2),
    CountyTaxableValue         DECIMAL(18,2),
    SchoolTaxableValue          DECIMAL(18,2),
    MunicipalTaxableValue       DECIMAL(18,2),
    OtherTaxableValue           DECIMAL(18,2),
    MillageArea               VARCHAR(50),
    CountyMillage             DECIMAL(8,4),
    SchoolMillage             DECIMAL(8,4),
    MunicipalMillage          DECIMAL(8,4),
    OtherMillage              DECIMAL(8,4),
    CountyTaxes              DECIMAL(18,2),
    SchoolTaxes              DECIMAL(18,2),
    MunicipalTaxes           DECIMAL(18,2),
    OtherTaxes               DECIMAL(18,2),
    TotalAdvTaxes            DECIMAL(18,2),
    TotalNadvTaxes           DECIMAL(18,2),
    TotalTaxes               DECIMAL(18,2),
    GisFlnNum            VARCHAR(50),
    RowCheckSum          BIGINT,
    CreatedAt            TIMESTAMP        DEFAULT CURRENT_TIMESTAMP,
    UpdatedAt            TIMESTAMP        DEFAULT CURRENT_TIMESTAMP
);
SQL
}

RAW_TOTAL_ROWS=0
RAW_TOTAL_COLUMNS=0
PROPERTY_TOTAL_ROWS=0
PROPERTY_TOTAL_COLUMNS=0

DEFAULT_INPUT="${1:-}"
DEFAULT_EXCEL_SHEET="${2:-}"

declare -a SELECTED_FILES=()
declare -A FILE_SHEETS=()

if [[ -n "$DEFAULT_INPUT" ]]; then
  if [[ "$DEFAULT_INPUT" == /* ]]; then
    resolved_path="$DEFAULT_INPUT"
  else
    resolved_path="$SCRIPT_DIR/$DEFAULT_INPUT"
  fi
  if [[ ! -f "$resolved_path" ]]; then
    echo "ERROR: Provided dataset file not found: $DEFAULT_INPUT"
    exit 1
  fi
  SELECTED_FILES+=("$resolved_path")

  ext="${resolved_path##*.}"
  ext_lower="$(printf "%s" "$ext" | tr '[:upper:]' '[:lower:]')"
  if [[ "$ext_lower" == "xlsx" || "$ext_lower" == "xls" ]]; then
    sheet_choice="$DEFAULT_EXCEL_SHEET"
    if [[ -z "$sheet_choice" ]]; then
      read -r -p "Enter Excel sheet name or index to load (press Enter for the first sheet): " sheet_choice
    else
      read -r -p "Enter Excel sheet name or index to load (press Enter to use '$sheet_choice'): " sheet_input
      if [[ -n "$sheet_input" ]]; then
        sheet_choice="$sheet_input"
      fi
    fi
    FILE_SHEETS["$resolved_path"]="$sheet_choice"
  fi
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
    echo "You may select multiple files separated by spaces or commas (e.g., 1 2 5)."
    read -r -p "Select dataset file(s) [1-${#DATASET_FILES[@]}]: " selection

    selection="${selection//,/ }"
    selection="${selection//;/ }"
    selection="${selection//:/ }"
    selection="${selection//$'\t'/ }"
    selection="$(printf '%s' "$selection" | xargs 2>/dev/null || true)"

    if [[ -z "$selection" ]]; then
      echo "No selection detected. Please choose at least one dataset."
      continue
    fi

    IFS=' ' read -r -a selection_parts <<< "$selection"
    declare -A seen_indices=()
    valid=true
    SELECTED_FILES=()
    for token in "${selection_parts[@]}"; do
      if [[ ! "$token" =~ ^[0-9]+$ ]]; then
        valid=false
        break
      fi
      numeric=$((token))
      if (( numeric < 1 || numeric > ${#DATASET_FILES[@]} )); then
        valid=false
        break
      fi
      if [[ -z "${seen_indices[$numeric]-}" ]]; then
        seen_indices[$numeric]=1
        SELECTED_FILES+=("${DATASET_FILES[numeric-1]}")
      fi
    done

    if ! $valid; then
      echo "Invalid selection. Please choose numbers between 1 and ${#DATASET_FILES[@]}."
      SELECTED_FILES=()
      continue
    fi

    if (( ${#SELECTED_FILES[@]} == 0 )); then
      echo "No dataset files selected."
      continue
    fi

    break
  done

  for file_path in "${SELECTED_FILES[@]}"; do
    ext="${file_path##*.}"
    ext_lower="$(printf "%s" "$ext" | tr '[:upper:]' '[:lower:]')"
    if [[ "$ext_lower" == "xlsx" || "$ext_lower" == "xls" ]]; then
      display_name="${file_path#"$SCRIPT_DIR"/}"
      [[ -z "$display_name" ]] && display_name="$(basename "$file_path")"
      read -r -p "Enter Excel sheet for '$display_name' (press Enter for the first sheet): " sheet_choice
      FILE_SHEETS["$file_path"]="$sheet_choice"
    fi
  done
fi

mkdir -p "$OUTDIR"
: > "$MERGE_LOG"

echo "Selected dataset files:"
for file_path in "${SELECTED_FILES[@]}"; do
  display_name="${file_path#"$SCRIPT_DIR"/}"
  [[ -z "$display_name" ]] && display_name="$(basename "$file_path")"
  ext="${file_path##*.}"
  ext_lower="$(printf "%s" "$ext" | tr '[:upper:]' '[:lower:]')"
  sheet_note=""
  if [[ "$ext_lower" == "xlsx" || "$ext_lower" == "xls" ]]; then
    sheet_value="${FILE_SHEETS[$file_path]-}"
    if [[ -n "$sheet_value" ]]; then
      sheet_note=" (sheet: $sheet_value)"
    else
      sheet_note=" (sheet: <first>)"
    fi
  fi
  printf '  - %s%s\n' "$display_name" "$sheet_note"
done
echo

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

rationalize_dataset() {
  echo "Rationalizing source data into the PropertyListing schema..."

  mapfile -t source_columns < <(duckdb "$LOCAL_DB_PATH" <<SQL
.headers off
.mode list
SELECT lower(name) || '=' || name
FROM pragma_table_info('$LOCAL_TABLE_NAME');
.quit
SQL
  )

  declare -A SOURCE_COLUMN_LOOKUP=()
  for entry in "${source_columns[@]}"; do
    [[ -z "$entry" ]] && continue
    local original="${entry#*=}"
    local normalized
    normalized="$(normalize_column_name "$original")"
    [[ -z "$normalized" ]] && continue
    if [[ -z "${SOURCE_COLUMN_LOOKUP[$normalized]-}" ]]; then
      SOURCE_COLUMN_LOOKUP["$normalized"]="$original"
    fi
  done

  MERGE_MAPPED_FIELDS=()
  MERGE_DEFAULTED_FIELDS=()

  local select_body=""
  local column_list=""

  for column_def in "${PROPERTY_LISTING_COLUMNS[@]}"; do
    IFS='|' read -r column_name column_type <<< "$column_def"
    local normalized_target
    normalized_target="$(normalize_column_name "$column_name")"

    local candidates=("$normalized_target")
    if [[ -n "${PROPERTY_LISTING_ALIAS_MAP[$normalized_target]-}" ]]; then
      IFS='|' read -r -a alias_candidates <<< "${PROPERTY_LISTING_ALIAS_MAP[$normalized_target]}"
      candidates+=("${alias_candidates[@]}")
    fi

    local found=""
    for candidate in "${candidates[@]}"; do
      local candidate_norm
      candidate_norm="$(normalize_column_name "$candidate")"
      local actual="${SOURCE_COLUMN_LOOKUP[$candidate_norm]-}"
      if [[ -n "$actual" ]]; then
        found="$actual"
        break
      fi
    done

    local expr=""
    local upper_type
    upper_type="$(printf '%s' "$column_type" | tr '[:lower:]' '[:upper:]')"

    case "$column_name" in
      ListingID)
        if [[ -n "$found" ]]; then
          expr="COALESCE(NULLIF(TRIM(CAST(src.\"$found\" AS VARCHAR)), ''), printf('PL-%010d', src.__row_num)) AS \"$column_name\""
          MERGE_MAPPED_FIELDS+=("$column_name <- $found (fallback to generated ID)")
        else
          expr="printf('PL-%010d', src.__row_num) AS \"$column_name\""
          MERGE_DEFAULTED_FIELDS+=("$column_name (generated internal ID)")
        fi
        ;;
      CreatedAt)
        if [[ -n "$found" ]]; then
          expr="COALESCE(TRY_CAST(NULLIF(TRIM(src.\"$found\"), '') AS TIMESTAMP), CURRENT_TIMESTAMP) AS \"$column_name\""
          MERGE_MAPPED_FIELDS+=("$column_name <- $found (default CURRENT_TIMESTAMP)")
        else
          expr="CURRENT_TIMESTAMP AS \"$column_name\""
          MERGE_DEFAULTED_FIELDS+=("$column_name (default CURRENT_TIMESTAMP)")
        fi
        ;;
      UpdatedAt)
        if [[ -n "$found" ]]; then
          expr="COALESCE(TRY_CAST(NULLIF(TRIM(src.\"$found\"), '') AS TIMESTAMP), CURRENT_TIMESTAMP) AS \"$column_name\""
          MERGE_MAPPED_FIELDS+=("$column_name <- $found (default CURRENT_TIMESTAMP)")
        else
          expr="CURRENT_TIMESTAMP AS \"$column_name\""
          MERGE_DEFAULTED_FIELDS+=("$column_name (default CURRENT_TIMESTAMP)")
        fi
        ;;
      *)
        if [[ -n "$found" ]]; then
          if [[ "$upper_type" =~ ^(VARCHAR|CHAR|TEXT) ]]; then
            expr="NULLIF(TRIM(CAST(src.\"$found\" AS $column_type)), '') AS \"$column_name\""
          elif [[ "$upper_type" == "DATE" ]]; then
            expr="TRY_CAST(NULLIF(TRIM(src.\"$found\"), '') AS DATE) AS \"$column_name\""
          elif [[ "$upper_type" == "TIMESTAMP" ]]; then
            expr="TRY_CAST(NULLIF(TRIM(src.\"$found\"), '') AS TIMESTAMP) AS \"$column_name\""
          else
            expr="TRY_CAST(NULLIF(TRIM(src.\"$found\"), '') AS $column_type) AS \"$column_name\""
          fi
          MERGE_MAPPED_FIELDS+=("$column_name <- $found")
        else
          if [[ "$upper_type" == "TIMESTAMP" ]]; then
            expr="CAST(NULL AS TIMESTAMP) AS \"$column_name\""
          else
            expr="CAST(NULL AS $column_type) AS \"$column_name\""
          fi
          MERGE_DEFAULTED_FIELDS+=("$column_name")
        fi
        ;;
    esac

    if [[ -z "$select_body" ]]; then
      select_body="  $expr"
    else
      select_body="$select_body,"$'\n'"  $expr"
    fi

    if [[ -z "$column_list" ]]; then
      column_list="  \"$column_name\""
    else
      column_list="$column_list,"$'\n'"  \"$column_name\""
    fi
  done

  local create_sql
  create_sql="$(property_listing_create_sql)"

  duckdb "$LOCAL_DB_PATH" <<SQL
BEGIN TRANSACTION;
DROP VIEW IF EXISTS v_property_listing;
DROP TABLE IF EXISTS PropertyListing;
$create_sql
INSERT INTO PropertyListing (
$column_list
)
SELECT
$select_body
FROM (
  SELECT sd.*, ROW_NUMBER() OVER () AS __row_num
  FROM "$LOCAL_TABLE_NAME" AS sd
) AS src;
CREATE OR REPLACE VIEW v_property_listing AS SELECT * FROM PropertyListing;
CREATE OR REPLACE VIEW v_raw_all AS SELECT * FROM "$LOCAL_TABLE_NAME";
CREATE OR REPLACE VIEW v_all AS SELECT * FROM PropertyListing;
COMMIT;
.quit
SQL

  RAW_TOTAL_ROWS=$(duckdb "$LOCAL_DB_PATH" <<SQL
.headers off
.mode list
SELECT COUNT(*) FROM "$LOCAL_TABLE_NAME";
.quit
SQL
  )
  RAW_TOTAL_ROWS="$(printf '%s' "$RAW_TOTAL_ROWS" | tr -d '\n\r')"

  RAW_TOTAL_COLUMNS=$(duckdb "$LOCAL_DB_PATH" <<SQL
.headers off
.mode list
SELECT COUNT(*) FROM pragma_table_info('$LOCAL_TABLE_NAME');
.quit
SQL
  )
  RAW_TOTAL_COLUMNS="$(printf '%s' "$RAW_TOTAL_COLUMNS" | tr -d '\n\r')"

  PROPERTY_TOTAL_ROWS=$(duckdb "$LOCAL_DB_PATH" <<SQL
.headers off
.mode list
SELECT COUNT(*) FROM PropertyListing;
.quit
SQL
  )
  PROPERTY_TOTAL_ROWS="$(printf '%s' "$PROPERTY_TOTAL_ROWS" | tr -d '\n\r')"

  PROPERTY_TOTAL_COLUMNS=$(duckdb "$LOCAL_DB_PATH" <<SQL
.headers off
.mode list
SELECT COUNT(*) FROM pragma_table_info('PropertyListing');
.quit
SQL
  )
  PROPERTY_TOTAL_COLUMNS="$(printf '%s' "$PROPERTY_TOTAL_COLUMNS" | tr -d '\n\r')"

  log_merge "=== Merge Summary ($(date)) ==="
  for file_path in "${SELECTED_FILES[@]}"; do
    display_name="${file_path#"$SCRIPT_DIR"/}"
    [[ -z "$display_name" ]] && display_name="$(basename "$file_path")"
    log_merge "Source file: $display_name"
  done

  log_merge ""
  log_merge "Row counts by source file:"
  duckdb "$LOCAL_DB_PATH" <<SQL | tee -a "$MERGE_LOG"
.headers on
.mode box
SELECT COALESCE(__source_file, '<<unknown>>') AS source_file,
       COUNT(*) AS row_count
FROM "$LOCAL_TABLE_NAME"
GROUP BY 1
ORDER BY 1;
.quit
SQL

  log_merge ""
  log_merge "Raw dataset rows: $RAW_TOTAL_ROWS (columns: $RAW_TOTAL_COLUMNS)"
  log_merge "PropertyListing rows: $PROPERTY_TOTAL_ROWS (columns: $PROPERTY_TOTAL_COLUMNS)"

  if (( ${#MERGE_MAPPED_FIELDS[@]} > 0 )); then
    log_merge ""
    log_merge "Columns mapped from source (${#MERGE_MAPPED_FIELDS[@]}):"
    for mapped in "${MERGE_MAPPED_FIELDS[@]}"; do
      log_merge "  - $mapped"
    done
  fi

  if (( ${#MERGE_DEFAULTED_FIELDS[@]} > 0 )); then
    log_merge ""
    log_merge "Columns defaulted or generated (${#MERGE_DEFAULTED_FIELDS[@]}):"
    for missing in "${MERGE_DEFAULTED_FIELDS[@]}"; do
      log_merge "  - $missing"
    done
  else
    log_merge ""
    log_merge "All PropertyListing columns were populated from the source data."
  fi

  log_merge ""
  log_merge "Normalized view available as PropertyListing (v_all)."
  log_merge "Raw combined source table stored as $LOCAL_TABLE_NAME."
  log_merge ""
}

load_dataset_into_local_db
rationalize_dataset

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

echo "Raw dataset dimensions: ${RAW_TOTAL_ROWS} rows × ${RAW_TOTAL_COLUMNS} columns"
echo "PropertyListing dimensions: ${TOTAL_ROWS} rows × ${TOTAL_COLUMNS} columns"
echo "Merge summary log: $MERGE_LOG"
echo
echo "Column overview (PropertyListing):"
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
  echo "  6) Show the first 50 rows"
  echo "  7) Show the last 50 rows"
  echo "  8) Show every 20th row"
  echo "  L) LLM Prompt and Analysis"
  echo "  0) Quit"
  read -r -p "Enter choice [0-8, L]: " choice

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
          --argjson schema "$RESPONSE_SCHEMA" \
          '{
            contents: [
              {
                role: "user",
                parts: [
                  {
                    text: ($inst + "\n\n" + $cols + "\n\n" + $req)
                  }
                ]
              }
            ],
            generationConfig: {
              responseMimeType: "application/json",
              responseSchema: $schema
            }
          }' )

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

        generated=$(RESPONSE_BODY="$response_body" python3 - <<'PY'
import base64
import json
import os
import sys

raw_body = os.environ.get("RESPONSE_BODY", "")
if not raw_body.strip():
    sys.exit(0)

try:
    data = json.loads(raw_body)
except json.JSONDecodeError:
    sys.exit(0)

def iter_text_parts(response):
    for candidate in response.get("candidates", []) or []:
        content = candidate.get("content") or {}
        for part in content.get("parts") or []:
            text = part.get("text")
            if isinstance(text, str) and text.strip():
                yield text
            inline = part.get("inlineData") or part.get("inline_data")
            if isinstance(inline, dict):
                data_field = inline.get("data")
                if not data_field:
                    continue
                try:
                    decoded = base64.b64decode(data_field).decode("utf-8", "ignore")
                except Exception:
                    continue
                if decoded.strip():
                    yield decoded
            fn_call = part.get("functionCall") or part.get("function_call")
            if isinstance(fn_call, dict):
                args = fn_call.get("args")
                if isinstance(args, str) and args.strip():
                    yield args
                elif isinstance(args, dict):
                    yield json.dumps(args)
    fallback_text = response.get("outputText")
    if isinstance(fallback_text, str) and fallback_text.strip():
        yield fallback_text

for item in iter_text_parts(data):
    sys.stdout.write(item)
    break
PY
)
        generated=$(printf '%s' "$generated" | strip_code_fences)
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
      echo "--- Show the first 50 rows ---"
      output_file="$(make_output_file 6)"
      duckdb "$LOCAL_DB_PATH" <<SQL | tee "$output_file"
.headers on
.mode box
SELECT *
FROM "$LOCAL_TABLE_NAME"
ORDER BY rowid
LIMIT 50;
.quit
SQL
      echo "Result: $output_file"
      ;;
    7)
      echo "--- Show the last 50 rows ---"
      output_file="$(make_output_file 7)"
      duckdb "$LOCAL_DB_PATH" <<SQL | tee "$output_file"
.headers on
.mode box
WITH last_rowids AS (
  SELECT rowid
  FROM "$LOCAL_TABLE_NAME"
  ORDER BY rowid DESC
  LIMIT 50
)
SELECT *
FROM "$LOCAL_TABLE_NAME"
WHERE rowid IN (SELECT rowid FROM last_rowids)
ORDER BY rowid;
.quit
SQL
      echo "Result: $output_file"
      ;;
    8)
      echo "--- Show every 20th row ---"
      output_file="$(make_output_file 8)"
      duckdb "$LOCAL_DB_PATH" <<SQL | tee "$output_file"
.headers on
.mode box
SELECT *
FROM "$LOCAL_TABLE_NAME"
WHERE rowid % 20 = 0
ORDER BY rowid;
.quit
SQL
      echo "Result: $output_file"
      ;;
    *)
      echo "Invalid choice: $choice"
      ;;
  esac
done

echo "Done. All output in $OUTDIR"
