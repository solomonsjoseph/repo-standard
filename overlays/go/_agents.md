
### Go

| Task | Command |
|---|---|
| Format | `gofmt -w .` |
| Lint | `go vet ./...` and `golangci-lint run` |
| Test | `go test -race ./...` |
| Build | `go build ./...` |

Code that other modules may import goes in `pkg/`; everything else stays in
`internal/`.
