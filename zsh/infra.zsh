# infra — local Redis / Kafka / kafka-ui / Jaeger (compose file: ~/.config/devinfra/compose.yaml)
#   infra up            start everything, wait until healthy
#   infra down          stop (data kept)        infra reset   stop + delete data volumes
#   infra ps | logs -f  any other docker compose subcommand
#   infra kafka kafka-topics.sh --bootstrap-server localhost:9092 --list   (Kafka CLI inside the broker)
# Endpoints: redis://localhost:6379  kafka localhost:9092  kafka-ui http://localhost:8088
#            jaeger http://localhost:16686  OTLP localhost:4317 (gRPC) / :4318 (HTTP)
infra() {
  local -a dc=(docker compose -f ~/.config/devinfra/compose.yaml)
  (( $# )) || set -- ps
  case $1 in
    up)    shift; $dc up -d --wait "$@" ;;
    reset) $dc down -v ;;
    kafka) shift; $dc exec kafka /opt/kafka/bin/"$@" ;;
    *)     $dc "$@" ;;
  esac
}
