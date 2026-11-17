
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
installs with `pnpm install --frozen-lockfile`. TypeScript stays on 6.0.x
(`~6.0.0`, and Dependabot ignores newer versions) until typescript-eslint
supports a newer one; do not upgrade it on its own. `tsconfig.json`
type-checks sources, tests and config; `tsconfig.build.json` builds `src/`.
