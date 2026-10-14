# Project tools and MCP servers

A tool is global when it behaves the same in every project, and per project
when its version has to match CI. Per-project versions mean an agent in the
project runs the same linter CI runs. The same split applies to MCP servers:
they are configured per project and point at the local stack from
[Local infrastructure](local-infra.md).

## Global tools

Global tools come from the `Brewfile` and from `~/.config/mise/config.toml`,
which links to `mise/config.toml`:

```toml
[tools]
node = "lts"
pnpm = "latest"
"go:golang.org/x/tools/gopls" = "latest"
"go:github.com/go-delve/delve/cmd/dlv" = "latest"
"go:gotest.tools/gotestsum" = "latest"
"go:golang.org/x/vuln/cmd/govulncheck" = "latest"
```

Go itself is not managed by Homebrew or mise. It comes from the official
installer in `/usr/local/go`, and each `go.mod` `toolchain` line selects the
version a project builds with.

## Per-project tools in `mise.toml`

Linters, formatters, compilers and code generators go in the project's
`mise.toml`, `package.json` or `go.mod`. A `mise.toml` for a Go service with
a TypeScript frontend:

```toml
[tools]
node = "22"
golangci-lint = "2.5.0"
biome = "2.2.4"
buf = "1.57.2"

[env]
OTEL_EXPORTER_OTLP_ENDPOINT = "http://localhost:4318"

[tasks.setup]
run = ["mise install", "pnpm install --frozen-lockfile"]

[tasks.lint]
run = ["golangci-lint run ./...", "biome check ."]
```

Trust it once in the main checkout, then install and run tasks:

```sh
mise trust
mise install
mise run lint
mise tasks
```

JavaScript tools such as `typescript`, `tsx` and eslint stay in
`devDependencies`, pinned by the lockfile, and run through the package
manager with `pnpm exec tsc --noEmit`.

Workspaces created with `jw` inherit the trust. Because this file has a
`setup` task, `jw` runs `mise run setup` in every new workspace instead of
the automatic install steps, see
[Parallel agents](parallel-agents.md#what-a-new-workspace-gets).

## Go tools with the `tool` directive

Go 1.24 and later record tools in `go.mod`. Add one with `go get -tool` and
run it with `go tool`:

```sh
go get -tool github.com/bufbuild/buf/cmd/buf@v1.57.2
go tool buf lint
```

The version is in `go.mod` and `go.sum`, so CI and every agent get the same
build of the tool.

## MCP servers: per project, local, read-only

Add MCP servers for Redis, Kafka and similar services to the project, never
to the global Claude Code config, and never point them at staging or
production. Point them at the `infra` endpoints and turn on read-only mode
where the server has one. A checked-in `.mcp.json` at the project root:

```json
{
  "mcpServers": {
    "redis-local": {
      "command": "<redis MCP server command>",
      "args": ["<flags for read-only mode>"],
      "env": { "REDIS_URL": "redis://localhost:6379" }
    }
  }
}
```

The command and flags depend on the server you choose. `claude mcp add` with
`--scope project` writes the same file:

```sh
claude mcp add --scope project redis-local -- <command> [args...]
```

Claude Code asks you to approve project servers the first time it starts in
that repo.
