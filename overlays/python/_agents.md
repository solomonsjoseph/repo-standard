
### Python (uv)

| Task | Command |
|---|---|
| Set up | `uv sync --all-extras --dev` |
| Lint | `uv run ruff check .` |
| Format | `uv run ruff format .` |
| Type check | `uv run mypy src` |
| Test | `uv run pytest --cov` |

Add dependencies with `uv add` (or `uv add --dev`) so `uv.lock` stays in
sync; CI installs with `uv sync --locked`.
