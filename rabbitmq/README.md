# RabbitMQ Configuration - Eagle Platform

## Visão Geral

RabbitMQ configurado com **práticas modernas** e **sem features deprecated**.

## Configurações Modernas Aplicadas

### ✅ Quorum Queues (Recomendado)

Todas as filas usam **Quorum Queues** ao invés de Classic Queues com mirroring:

```json
{
  "arguments": {
    "x-queue-type": "quorum",
    "x-message-ttl": 86400000,
    "x-dead-letter-exchange": "eagle.dlx"
  }
}
```

**Benefícios:**
- ✅ Maior durabilidade e consistência
- ✅ Melhor performance em clusters
- ✅ Não usa `queue_master_locator` (deprecated)
- ✅ Replicação automática entre nós

### ✅ Prometheus Metrics (Recomendado)

Métricas expostas via plugin Prometheus ao invés de management metrics collection:

```properties
prometheus.tcp.port = 15692
```

**Acesso:** http://localhost:15692/metrics

**Benefícios:**
- ✅ Formato padrão da indústria
- ✅ Integração nativa com Grafana
- ✅ Melhor performance
- ✅ Não usa `management_metrics_collection` (deprecated)

### ✅ Configuração via Arquivo

Todas as configurações estão em `rabbitmq.conf` ao invés de variáveis de ambiente:

```properties
# ✅ CORRETO (arquivo de configuração)
vm_memory_high_watermark.relative = 0.6
disk_free_limit.absolute = 2GB

# ❌ ERRADO (variável de ambiente deprecated)
# RABBITMQ_VM_MEMORY_HIGH_WATERMARK=0.6
# RABBITMQ_DISK_FREE_LIMIT=2GB
```

## Estrutura de Filas

### Filas Principais

| Fila | Tipo | TTL | Descrição |
|------|------|-----|-----------|
| `alert.events` | quorum | 24h | Eventos de alertas |
| `customer.events` | quorum | 24h | Eventos de clientes |
| `transaction.events` | quorum | 24h | Eventos de transações |
| `rules.events` | quorum | 24h | Eventos de regras |
| `analytics.all` | quorum | 7d | **Todos** os eventos (ms-analytics) |
| `orchestrator.events` | quorum | 7d | Eventos de orquestração |

### Dead Letter Queues

| Fila | Descrição |
|------|-----------|
| `eagle.dlq` | DLQ geral para inspeção manual |
| `orchestrator.events.dlq` | DLQ específica do orchestrator |

## Exchanges

| Exchange | Tipo | Descrição |
|----------|------|-----------|
| `eagle.events` | topic | Exchange principal para todos os eventos |
| `eagle.dlx` | topic | Dead Letter Exchange |

## Bindings

### Filas Específicas por Domínio

```
eagle.events (topic exchange)
├─ alert.*           → alert.events
├─ customer.*        → customer.events
├─ transaction.*     → transaction.events
└─ rules.*           → rules.events
```

### Filas Agregadas

```
eagle.events (topic exchange)
├─ #                 → analytics.all (TODOS os eventos)
├─ alert.*           → orchestrator.events
├─ customer.*        → orchestrator.events
└─ dossier.*         → orchestrator.events
```

## Acesso

### Management UI
```
URL: http://localhost:15672
User: fusionx
Password: fusionx2024
```

### Prometheus Metrics
```
URL: http://localhost:15692/metrics
```

### AMQP Protocol
```
Host: localhost
Port: 5672
User: fusionx
Password: fusionx2024
VHost: /
```

## Comandos Úteis

### Verificar Status
```bash
docker exec fx-rabbitmq rabbitmq-diagnostics status
docker exec fx-rabbitmq rabbitmqctl cluster_status
```

### Listar Filas
```bash
docker exec fx-rabbitmq rabbitmqctl list_queues name messages consumers
```

### Listar Exchanges
```bash
docker exec fx-rabbitmq rabbitmqctl list_exchanges name type
```

### Listar Bindings
```bash
docker exec fx-rabbitmq rabbitmqctl list_bindings
```

### Publicar Evento de Teste
```bash
docker exec fx-rabbitmq rabbitmqadmin publish \
  exchange=eagle.events \
  routing_key=alert.created.v1 \
  payload='{"event_id":"test-123","event_type":"alert.created.v1","timestamp":"2025-11-20T10:30:00Z","source_service":"test","payload":{}}'
```

### Consumir Mensagem de Teste
```bash
docker exec fx-rabbitmq rabbitmqadmin get queue=analytics.all count=1
```

## Monitoramento

### Health Check
```bash
docker exec fx-rabbitmq rabbitmq-diagnostics ping
docker exec fx-rabbitmq rabbitmq-diagnostics check_running
```

### Métricas Importantes

Via Prometheus (http://localhost:15692/metrics):
- `rabbitmq_queue_messages` - Mensagens na fila
- `rabbitmq_queue_consumers` - Consumidores ativos
- `rabbitmq_connections` - Conexões ativas
- `rabbitmq_channels` - Canais abertos

## Troubleshooting

### Container reiniciando
```bash
docker logs fx-rabbitmq --tail 100
```

### Filas não criadas
```bash
# Verificar se definitions.json foi carregado
docker exec fx-rabbitmq cat /etc/rabbitmq/definitions.json
```

### Mensagens não sendo roteadas
```bash
# Verificar bindings
docker exec fx-rabbitmq rabbitmqctl list_bindings source_name destination_name routing_key
```

## Migração de Features Deprecated

### ✅ Já Migrado

- ❌ `queue_master_locator` → ✅ Quorum Queues
- ❌ `RABBITMQ_VM_MEMORY_HIGH_WATERMARK` (env var) → ✅ `vm_memory_high_watermark.relative` (config file)
- ❌ Classic Queue Mirroring → ✅ Quorum Queues

### ⚠️ Pendente (TODO)

- ⚠️ `management_metrics_collection` → Migrar 100% para Prometheus
  - Atualmente: Permitido temporariamente
  - Ação: Desabilitar management metrics e usar apenas Prometheus

## Referências

- [RabbitMQ 3.13 Release Notes](https://www.rabbitmq.com/release-information)
- [Quorum Queues](https://www.rabbitmq.com/quorum-queues.html)
- [Prometheus Plugin](https://www.rabbitmq.com/prometheus.html)
- [Configuration File](https://www.rabbitmq.com/configure.html)
