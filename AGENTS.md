# Repository Contribution Guidelines

## Documentation updates
- Use descriptive section headers written in sentence case (capitalize only the first word and proper nouns).
- Prefer bulleted lists for command sequences or option summaries; fall back to numbered steps for workflows that must occur in order.
- Keep `README.md` synchronized with `analyze_csv.sh`, especially the Quickstart, Usage, Normalization workflow, Menu reference, and Logging outputs sections.
- When referencing repository files, use backticks around filenames and relative paths.

## Shell scripting changes
- Keep Bash scripts POSIX-compatible unless a feature explicitly requires Bash extensions.
- Avoid adding external dependencies without documenting them in `README.md`.
- Comment non-obvious environment variables or `duckdb` pragmas directly above their usage.

## Repository overview
- `analyze_csv.sh` loads one or more CSV/TXT/Excel files, infers metadata, and normalizes them into the `PropertyListing` table within `local.duckdb` while maintaining helper views (`v_all`, `v_property_listing`, `v_raw_all`).
- `scripts/spreadsheet_logger.py` mirrors stdout to semicolon-delimited logs (`script-run.log`, `analysis-results.log`, `merge-summary.log`, and files in `output/`).
- The loader records merge details (mapped columns, defaults, per-source counts) in `merge-summary.log`; update documentation when the schema or logging format changes.

