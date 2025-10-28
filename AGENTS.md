# Repository Contribution Guidelines

## Documentation updates
- Use descriptive section headers written in sentence case (capitalize only the first word and proper nouns).
- Prefer bulleted lists for command sequences or option summaries; fall back to numbered steps for workflows that must occur in order.
- When referencing repository files, use backticks around filenames and relative paths.

## Shell scripting changes
- Keep Bash scripts POSIX-compatible unless a feature explicitly requires Bash extensions.
- Avoid adding external dependencies without documenting them in `README.md`.
- Comment non-obvious environment variables or `duckdb` pragmas directly above their usage.

These conventions apply to the entire repository.
