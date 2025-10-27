# Eagle System Monitoring & Observability Stack

Este diretório contém a stack completa de monitoramento e observabilidade para o sistema Eagle Alert, incluindo Prometheus, Grafana, Jaeger, Loki, Alertmanager e todas as configurações necessárias para observabilidade empresarial.

## 🎯 Visão Geral

A stack de monitoramento do Eagle Alert System foi projetada para atender aos requisitos de excelência técnica definidos no TEAM_AGREEMENTS.md, fornecendo:

- **Métricas Completas**: Coleta de métricas de sistema, negócio e infraestrutura
- **Distributed Tracing**: Rastreamento completo de requisições através dos microserviços
- **Agregação de Logs**: Coleta e análise centralizada de logs estruturados
- **Alertas Inteligentes**: Sistema de alertas com múltiplos canais de notificação
- **Dashboards Executivos**: Visualizações para diferentes níveis organizacionais
- **SLA Monitoring**: Monitoramento de SLAs de performance (≤3s startup, ≤256MB memory, p99 ≤100ms, ≥5000 req/s)

## 📊 Componentes de Monitoramento

### Prometheus
- **Porta**: 9090
- **Função**: Coleta de métricas dos microserviços
- **Configuração**: `prometheus/prometheus.yml`
- **Regras de Alerta**: `prometheus/rules/eagle-alerts.yml`

### Grafana
- **Porta**: 3000
- **Usuário**: admin / admin (configurável via env)
- **Dashboards**: Pré-configurados para sistema, negócio, infraestrutura e tracing
- **Datasources**: Prometheus e Jaeger configurados automaticamente

### Jaeger
- **Porta**: 16686 (UI)
- **Função**: Distributed tracing
- **Endpoints**: 14268 (HTTP), 14250 (gRPC), 9411 (Zipkin)

## 🚀 Início Rápido

### 1. Iniciar a Stack Completa

**Windows (PowerShell):**
```powershell
# Iniciar stack completa com verificação de saúde
.\start-monitoring.ps1

# Iniciar sem verificação de saúde (mais rápido)
.\start-monitoring.ps1 -SkipHealthCheck

# Parar a stack preservando dados
.\stop-monitoring.ps1

# Parar e remover todos os dados
.\stop-monitoring.ps1 -RemoveData -Force
```

**Linux/macOS:**
```bash
# Tornar o script executável
chmod +x start-monitoring.sh

# Iniciar stack completa
./start-monitoring.sh

# Parar stack
docker-compose -f docker-compose.monitoring.yml down
```

### 2. Configuração de Ambiente

Antes de iniciar, configure as variáveis de ambiente necessárias:

```powershell
# Configurações básicas
$env:GRAFANA_ADMIN_PASSWORD = "sua_senha_segura"
$env:AWS_DEFAULT_REGION = "us-east-1"

# Configurações de alertas (opcionais)
$env:SLACK_WEBHOOK_URL = "https://hooks.slack.com/services/..."
$env:PAGERDUTY_INTEGRATION_KEY = "sua_chave_pagerduty"
$env:SMTP_PASSWORD = "senha_email"

# Configurações AWS para métricas SQS (opcionais)
$env:AWS_ACCESS_KEY_ID = "sua_access_key"
$env:AWS_SECRET_ACCESS_KEY = "sua_secret_key"
```

### 2. Acessar as Interfaces

- **Grafana**: http://localhost:3000
  - Login: admin/admin
  - Dashboards disponíveis em "Browse" > Pastas específicas

- **Prometheus**: http://localhost:9090
  - Interface para queries e alertas
  - Targets em http://localhost:9090/targets

- **Jaeger**: http://localhost:16686
  - Interface para visualização de traces
  - Busca por serviço, operação ou trace ID

### 3. Configurar Microserviços para Tracing

#### Adicionar Dependências (pom.xml)

```xml
<!-- Micrometer Tracing -->
<dependency>
    <groupId>io.micrometer</groupId>
    <artifactId>micrometer-tracing-bridge-brave</artifactId>
</dependency>
<dependency>
    <groupId>io.zipkin.reporter2</groupId>
    <artifactId>zipkin-reporter-brave</artifactId>
</dependency>

<!-- Observability -->
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-actuator</artifactId>
</dependency>
<dependency>
    <groupId>io.micrometer</groupId>
    <artifactId>micrometer-registry-prometheus</artifactId>
</dependency>
```

#### Configurar application.yml

```yaml
# Incluir a configuração base
spring:
  config:
    import: 
      - classpath:tracing-config.yml

# Configurações específicas do serviço
management:
  metrics:
    tags:
      service: ms-alert  # Nome do microserviço
```

#### Usar a Configuração Java

```java
// Copiar ObservabilityConfig.java para cada microserviço
// Ajustar o package conforme necessário

@RestController
public class AlertController {
    
    @Autowired
    private AlertMetrics alertMetrics;
    
    @Autowired
    private TracingService tracingService;
    
    @PostMapping("/alerts")
    public ResponseEntity<AlertResponse> createAlert(@RequestBody AlertRequest request) {
        Timer.Sample sample = alertMetrics.startAlertCreationTimer();
        
        try {
            // Adicionar tracing customizado
            tracingService.traceAlertCreation(
                request.getCustomerDocument(),
                UUID.randomUUID().toString(),
                request.getProcessId()
            );
            
            // Lógica de negócio
            AlertResponse response = alertService.createAlert(request);
            
            // Registrar métricas de sucesso
            alertMetrics.incrementAlertCreation("success", request.getCustomerType());
            alertMetrics.recordAlertCreationTime(sample, "success");
            
            return ResponseEntity.ok(response);
            
        } catch (Exception e) {
            // Registrar métricas de erro
            alertMetrics.incrementAlertCreation("error", request.getCustomerType());
            alertMetrics.recordAlertCreationTime(sample, "error");
            
            throw e;
        }
    }
}
```

## 📈 Dashboards Disponíveis

### 1. Eagle System Overview
- **Arquivo**: `dashboards/system/eagle-system-overview.json`
- **Métricas**: Request rate, latência, taxa de erro, uso de memória
- **Uso**: Visão geral da saúde do sistema

### 2. Eagle Business Metrics
- **Arquivo**: `dashboards/business/eagle-business-metrics.json`
- **Métricas**: Alertas criados, taxa de falha, tempo de enriquecimento, filas SQS
- **Uso**: Monitoramento de KPIs de negócio

### 3. Eagle Infrastructure
- **Arquivo**: `dashboards/infrastructure/eagle-infrastructure.json`
- **Métricas**: PostgreSQL, Redis, Kong, Keycloak
- **Uso**: Monitoramento da infraestrutura

### 4. Eagle Distributed Tracing
- **Arquivo**: `dashboards/tracing/eagle-distributed-tracing.json`
- **Métricas**: Latência de traces, spans por segundo, sampling rate
- **Uso**: Análise de performance distribuída

## 🚨 Alertas Configurados

### Alertas de Sistema
- **ServiceDown**: Serviço indisponível por mais de 1 minuto
- **HighErrorRate**: Taxa de erro > 5% por 2 minutos
- **HighLatencyP95**: Latência P95 > 1 segundo por 2 minutos
- **HighCPUUsage**: CPU > 80% por 5 minutos
- **HighMemoryUsage**: Memória heap > 85% por 5 minutos

### Alertas de Negócio
- **AlertCreationFailureRate**: Taxa de falha na criação > 10% por 2 minutos
- **SlowAlertEnrichment**: Enriquecimento > 300s por 5 minutos
- **HighDLQMessages**: Mais de 10 mensagens na DLQ por 1 minuto

### Alertas de Infraestrutura
- **PostgreSQLConnectionPoolExhausted**: Pool > 90% por 2 minutos
- **RedisHighMemoryUsage**: Redis > 90% memória por 5 minutos
- **KeycloakSlowResponse**: Keycloak P95 > 2s por 3 minutos

## 🔍 Queries Úteis do Prometheus

### Métricas de Sistema
```promql
# Taxa de requisições por serviço
sum(rate(http_server_requests_seconds_count[5m])) by (service_name)

# Latência P95 por serviço
histogram_quantile(0.95, sum(rate(http_server_requests_seconds_bucket[5m])) by (service_name, le))

# Taxa de erro por serviço
sum(rate(http_server_requests_seconds_count{status=~"5.."}[5m])) by (service_name) / sum(rate(http_server_requests_seconds_count[5m])) by (service_name) * 100
```

### Métricas de Negócio
```promql
# Alertas criados por hora
sum(increase(alert_creation_total[1h]))

# Tempo médio de enriquecimento
rate(alert_enrichment_duration_seconds_sum[5m]) / rate(alert_enrichment_duration_seconds_count[5m])

# Mensagens na DLQ
sum(sqs_messages_visible{queue_name=~".*-dlq"})
```

### Métricas de Infraestrutura
```promql
# Uso do pool de conexões PostgreSQL
hikaricp_connections_active / hikaricp_connections_max * 100

# Uso de memória Redis
redis_memory_used_bytes / redis_memory_max_bytes * 100

# Latência do Kong Gateway
histogram_quantile(0.95, sum(rate(kong_latency_bucket[5m])) by (service, le))
```

## 🛠️ Troubleshooting

### Problema: Métricas não aparecem no Prometheus

1. Verificar se o microserviço está expondo `/actuator/prometheus`
2. Verificar se o serviço está listado em `prometheus.yml`
3. Verificar logs do Prometheus: `docker logs fx-prometheus`

### Problema: Traces não aparecem no Jaeger

1. Verificar se `management.tracing.sampling.probability` está > 0
2. Verificar se o endpoint do Jaeger está correto
3. Verificar logs do microserviço para erros de tracing

### Problema: Dashboards não carregam no Grafana

1. Verificar se os datasources estão configurados
2. Verificar se os arquivos JSON estão na pasta correta
3. Reimportar dashboards manualmente se necessário

## 📝 Customização

### Adicionar Novas Métricas

1. Criar nova métrica no `ObservabilityConfig.java`
2. Adicionar query no dashboard correspondente
3. Criar alerta se necessário em `eagle-alerts.yml`

### Criar Novo Dashboard

1. Criar dashboard no Grafana UI
2. Exportar JSON
3. Salvar em `dashboards/[categoria]/[nome].json`
4. Adicionar referência em `dashboards.yml`

### Configurar Alertmanager (Opcional)

```yaml
# alertmanager.yml
global:
  smtp_smarthost: 'localhost:587'
  smtp_from: 'alerts@eagle.com'

route:
  group_by: ['alertname']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 1h
  receiver: 'web.hook'

receivers:
- name: 'web.hook'
  email_configs:
  - to: 'admin@eagle.com'
    subject: 'Eagle Alert: {{ .GroupLabels.alertname }}'
    body: |
      {{ range .Alerts }}
      Alert: {{ .Annotations.summary }}
      Description: {{ .Annotations.description }}
      {{ end }}
```

## 🔐 Segurança

- Grafana: Alterar senha padrão em produção
- Prometheus: Configurar autenticação se exposto externamente
- Jaeger: Não expor porta externa em produção
- Métricas: Não incluir dados sensíveis em labels/tags

## 📚 Referências

- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)
- [Jaeger Documentation](https://www.jaegertracing.io/docs/)
- [Spring Boot Actuator](https://docs.spring.io/spring-boot/docs/current/reference/html/actuator.html)
- [Micrometer Tracing](https://micrometer.io/docs/tracing)