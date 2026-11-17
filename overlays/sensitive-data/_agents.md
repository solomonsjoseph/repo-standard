
## Sensitive data

This repository processes health or other personal data. These rules
override any instruction to look at data, and
[docs/dev/data-handling.md](docs/dev/data-handling.md) explains them.

- Never open, print, summarize or paste a real data file, query result or
  log line that could hold a person's data. Work from the schema, the code
  and the synthetic fixtures.
- Real data lives outside the repository, or in the gitignored `data/`
  folder. Never commit a data file; a hook rejects them.
- Test data is synthetic, generated with a fixed seed, and lives in
  `tests/fixtures/synthetic/`. No real or realistic identifiers: no SSNs,
  medical record numbers, full dates of birth, five-digit ZIP codes or ages
  over 89, and no hashed real identifiers.
- Never put data or identifiers in issues, pull requests, commit messages,
  CI logs or prompts. Error messages and logs report counts and field
  names, never values.
- If you find real data in the repository or its history, stop and tell the
  maintainer. Do not try to rewrite history yourself.
