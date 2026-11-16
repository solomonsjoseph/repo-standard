
### TypeScript (pnpm)

| Task | Command |
|---|---|
| Set up | `pnpm install` |
| Lint | `pnpm run lint` |
| Format | `pnpm run format` |
| Type check | `pnpm run typecheck` |
| Test | `pnpm run test:coverage` |
| Build | `pnpm run build` |

Add dependencies with `pnpm add` so `pnpm-lock.yaml` stays in sync; CI
installs with `pnpm install --frozen-lockfile`.
