# Local infrastructure

`infra` runs Redis, Apache Kafka, kafka-ui and Jaeger in Docker for local
development. It wraps `docker compose -f ~/.config/devinfra/compose.yaml`,
which `install.sh` links to `infra/compose.yaml`, with the compose project
name `devinfra`. You need Docker Desktop or OrbStack running.

| Service | Image | Endpoint |
|---|---|---|
| Redis | `redis:8` | `localhost:6379` |
| Apache Kafka, KRaft, single node, 3 partitions per new topic | `apache/kafka:4.1.0` | `localhost:9092` |
| kafka-ui | `ghcr.io/kafbat/kafka-ui:latest` | http://localhost:8088 |
| Jaeger UI | `jaegertracing/jaeger:latest` | http://localhost:16686 |
| OTLP into Jaeger | | `localhost:4317` for gRPC, `localhost:4318` for HTTP |

Every port is published on `127.0.0.1` and on `[::1]`, and on nothing else.
Nothing is reachable from the network, and `localhost` works for clients that
try `::1` before `127.0.0.1`.

## Start and stop

```sh
infra up              # docker compose up -d --wait: start everything, wait until healthy
infra up redis        # start only Redis
infra                 # same as infra ps
infra logs -f kafka   # any other docker compose subcommand passes through
infra restart kafka-ui
infra down            # stop, keep the data volumes
infra reset           # docker compose down -v: stop and delete Redis and Kafka data
```

`infra up` waits on the health checks: `redis-cli ping` for Redis and
`kafka-broker-api-versions.sh` for Kafka. kafka-ui starts only after Kafka is
healthy. From the dotfiles repo, `just infra-up` and `just infra-down` run
the same stack straight from `infra/compose.yaml`.

## Redis

`redis-cli` comes from the `Brewfile`. The server runs in Docker:

```sh
redis-cli ping                                   # PONG
redis-cli set session:42 '{"user":1}' EX 300
redis-cli --scan --pattern 'session:*'
redis-cli monitor                                # every command your service sends
```

Redis Insight, also from the `Brewfile`, connects to `localhost:6379` for a
GUI.

## Kafka with the bundled CLI

`infra kafka <script> ...` runs `/opt/kafka/bin/<script>` inside the broker
container, so the scripts match the broker version:

```sh
infra kafka kafka-topics.sh --bootstrap-server localhost:9092 --list
infra kafka kafka-topics.sh --bootstrap-server localhost:9092 --create --topic orders --partitions 3
infra kafka kafka-topics.sh --bootstrap-server localhost:9092 --describe --topic orders
infra kafka kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --group order-service
infra kafka kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic orders --from-beginning
```

## Kafka with kcat

`kcat` talks to the broker from the host:

```sh
kcat -b localhost:9092 -L                                          # brokers, topics, partitions
echo 'order-1:{"id":1,"total":42}' | kcat -b localhost:9092 -t orders -P -K:
kcat -b localhost:9092 -t orders -C -o beginning -e                # consume everything, then exit
kcat -b localhost:9092 -t orders -C -o -5 -e -f 'p%p o%o key=%k %s\n'
```

`-K:` splits each input line into key and value at the first `:`. The last
command reads the five newest messages of each partition and prints the
partition, offset and key with each one.

The broker advertises `localhost:9092` to the host and `kafka:19092` to the
other containers, so a service running in the same compose network uses
`kafka:19092`.

kafka-ui at http://localhost:8088 has the broker preconfigured as the cluster
`local`. `DYNAMIC_CONFIG_ENABLED` is on, so you can add more clusters from the
UI.

## Tracing with Jaeger

Point any OpenTelemetry SDK at the OTLP endpoint:

```sh
export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318   # use :4317 for gRPC
export OTEL_SERVICE_NAME=my-service
```

Put the same values in the project's `mise.toml` so every shell and agent in
the project gets them, as shown in [Project tools](project-tools.md):

```toml
[env]
OTEL_EXPORTER_OTLP_ENDPOINT = "http://localhost:4318"
OTEL_SERVICE_NAME = "my-service"
```

Then open http://localhost:16686 and pick the service. Jaeger keeps traces in
memory, so they are gone after `infra down`.

## Rules for agents

The global `CLAUDE.md` lets agents use `infra`, `redis-cli`, `kcat` and the
Kafka scripts only against local or dev endpoints, and forbids `FLUSHALL`,
`FLUSHDB`, topic deletion and `infra reset` unless you ask for them. See
[Claude Code](claude-code.md).
