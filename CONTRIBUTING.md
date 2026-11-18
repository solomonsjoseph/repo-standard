# Contributing

This repository follows the
[repo standard](https://github.com/solomonsjoseph/repo-standard/blob/main/STANDARD.md).
The short version:

1. Open an issue for any feature or bug. Chores and docs may skip it.
2. Branch from `main`: `<type>/<issue>-<slug>`, for example `feat/12-csv-export`.
3. Install the hooks once per clone:

   ```bash
   pre-commit install
   ```

4. Commit with Conventional Commits: `type(scope): subject`, imperative and
   lowercase, with a body that explains why. Types: `feat`, `fix`, `perf`, `refactor`,
   `docs`, `test`, `build`, `ci`, `chore`, `revert`.
5. Open a pull request with the same title format and fill in every section
   of the template. Keep it small, around 100 changed lines.
6. The `ci` and `pr-title` checks must pass and every review conversation must
   be resolved. Pull requests are squash-merged.
7. Releases are automatic: release-please opens a release PR from the commits
   on `main`, and merging it publishes the version.

Source and config files are English and plain ASCII only; docs,
translations and test data may hold Unicode text, but no file may hold
hidden bidirectional or zero-width characters.

## AI tools

This project is developed with AI coding agents, and the maintainer
reviews every change before it merges. Contributions made with AI help are
welcome on the same terms:

- you understand every line you submit and can answer questions about it;
- you say in the pull request description, in plain words, when an AI tool
  wrote a significant part of the change;
- you do not submit changes produced by an autonomous agent without your
  own review.

Commits and pull request bodies carry no AI attribution lines
(`Co-Authored-By` naming an AI tool, "Generated with" footers, or
`Claude-Session:` trailers and lines that start with a session link);
a hook
and the `pr-title` check reject them.
