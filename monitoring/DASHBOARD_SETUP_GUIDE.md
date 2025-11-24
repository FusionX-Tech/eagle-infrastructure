# Eagle Flow Integration Dashboard - Setup Guide

## Quick Start

### 1. Start Monitoring Stack

```powershell
# Windows
cd Eagle\eagle-infrastructure\monitoring
.\start-monitoring.ps1

# Linux/Mac
cd Eagle/eagle-infrastructure/monitoring
./start-monitoring.sh
```

### 2. Verify Services

Aguarde todos os serviços subirem (aproximadamente 30 segundos):

```powershell
docker ps | Select-String "eagle-"
```

Você deve ver:
- eagle-prometheus (porta 9090)
- eagle-grafana (porta 3000)
- eagle-alertmanager (porta 9093)
- eagle-jaeger (porta 16686)

### 3. Access Grafana

1. Abra o navegador: http://localhost:3000
2. Login:
   - Username: `admin`
   - Password: `admin` (ou valor de `GRAFANA_ADMIN_PASSWORD` no .env)
3. Navegue para: **Dashboards → Eagle Infrastructure → Eagle Flow - Integration Health**

## Dashboard Location

O dashboard está localizado em:
```
Eagle/eagle-infrastructure/monitoring/grafana/dashboards/infrastructure/eagle-flow-integration-dashboard.json
```

## Auto-Loading

O dashboard é automaticamente carregado pelo Grafana através do provisioning configurado em:
```
Eagle/eagle-infrastructure/monitoring/grafana/provisioning/dashboards/dashboards.yml
```

Não é necessário importar manualmente!

## Verificar Métricas

### 1. Verificar se Eagle Flow está expondo métricas

```powershell
curl http://localhost:8092/actuator/prometheus | Select-String "eagle_flow"
```

Você deve ver métricas como:
- `eagle_flow_integration_calls_total`
- `eagle_flow_integration_duration_seconds`
- `eagle_flow_circuit_breaker_state`
- `eagle_flow_retry_attempts_total`

### 2. Verificar se Prometheus está coletando

1. Abra: http://localhost:9090
2. Vá para **Status → Targets**
3. Procure por `ms-eagle-flow` - deve estar **UP**

### 3. Testar Query no Prometheus

No Prometheus UI (http://localhost:9090), execute:

```promql
eagle_flow_integration_calls_total
```

Deve retornar dados se houver tráfego no Eagle Flow.

## Gerar Tráfego de Teste

Para popular o dashboard com dados, execute alguns testes:

```powershell
# Criar alerta simples
curl -X POST http://localhost:8092/api/v1/integrated-alerts/simple `
  -H "Content-Type: application/json" `
  -d '{}'

# Criar alerta com regras
curl -X POST http://localhost:8092/api/v1/integrated-alerts/with-rules `
  -H "Content-Type: application/json" `
  -d '{
    "ruleCount": 3,
    "severity": "HIGH"
  }'

# Verificar health
curl http://localhost:8092/api/v1/integrated-alerts/health
```

Após alguns minutos, o dashboard começará a mostrar dados.

## Troubleshooting

### Dashboard não aparece no Grafana

**Problema**: Dashboard não está listado em "Eagle Infrastructure"

**Solução**:
1. Verificar se arquivo existe:
   ```powershell
   Test-Path Eagle\eagle-infrastructure\monitoring\grafana\dashboards\infrastructure\eagle-flow-integration-dashboard.json
   ```

2. Reiniciar Grafana:
   ```powershell
   docker restart eagle-grafana
   ```

3. Verificar logs do Grafana:
   ```powershell
   docker logs eagle-grafana | Select-String "dashboard"
   ```

### Métricas não aparecem

**Problema**: Painéis mostram "No data"

**Solução**:
1. Verificar se Eagle Flow está rodando:
   ```powershell
   curl http://localhost:8092/actuator/health
   ```

2. Verificar se métricas estão sendo expostas:
   ```powershell
   curl http://localhost:8092/actuator/prometheus | Select-String "eagle_flow"
   ```

3. Verificar se Prometheus está coletando:
   - Abrir http://localhost:9090/targets
   - Procurar `ms-eagle-flow`
   - Deve estar **UP**

4. Verificar configuração do Prometheus:
   ```powershell
   cat Eagle\eagle-infrastructure\monitoring\prometheus.yml | Select-String "eagle-flow"
   ```

### Prometheus não está coletando do Eagle Flow

**Problema**: Target `ms-eagle-flow` está DOWN no Prometheus

**Solução**:
1. Verificar se Eagle Flow está na mesma rede Docker:
   ```powershell
   docker network inspect eagle-monitoring
   ```

2. Adicionar Eagle Flow ao prometheus.yml se não estiver:
   ```yaml
   scrape_configs:
     - job_name: 'ms-eagle-flow'
       metrics_path: '/actuator/prometheus'
       static_configs:
         - targets: ['fx-ms-eagle-flow:8092']
       scrape_interval: 15s
   ```

3. Recarregar configuração do Prometheus:
   ```powershell
   curl -X POST http://localhost:9090/-/reload
   ```

### Circuit Breaker State não aparece

**Problema**: Painel "Circuit Breaker State" mostra "No data"

**Solução**:
1. Verificar se métrica está sendo exposta:
   ```powershell
   curl http://localhost:8092/actuator/prometheus | Select-String "circuit_breaker_state"
   ```

2. Se não estiver, verificar se ResilientRestClient está registrando a métrica:
   - Verificar logs do Eagle Flow
   - Procurar por "Registering circuit breaker state metric"

3. Fazer uma chamada de integração para inicializar a métrica:
   ```powershell
   curl http://localhost:8092/api/v1/integrated-alerts/health
   ```

## Customização

### Adicionar Novos Painéis

1. Editar dashboard no Grafana UI
2. Salvar mudanças
3. Exportar JSON: **Dashboard Settings → JSON Model**
4. Copiar JSON para arquivo:
   ```powershell
   # Salvar em arquivo local
   Set-Content -Path "Eagle\eagle-infrastructure\monitoring\grafana\dashboards\infrastructure\eagle-flow-integration-dashboard.json" -Value $json
   ```

### Ajustar Thresholds

Edite o arquivo JSON e modifique os valores em `thresholds.steps`:

```json
"thresholds": {
  "steps": [
    {"color": "red", "value": 0},
    {"color": "yellow", "value": 90},
    {"color": "green", "value": 95}
  ]
}
```

### Adicionar Alertas

Edite `Eagle/eagle-infrastructure/monitoring/alert_rules.yml`:

```yaml
groups:
  - name: eagle_flow_integration
    rules:
      - alert: HighIntegrationErrorRate
        expr: |
          sum(rate(eagle_flow_integration_calls_total{status="failure"}[5m])) by (service)
          / sum(rate(eagle_flow_integration_calls_total[5m])) by (service) * 100 > 5
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "High error rate on {{ $labels.service }}"
```

Recarregar Prometheus:
```powershell
curl -X POST http://localhost:9090/-/reload
```

## Backup e Restore

### Backup do Dashboard

```powershell
# Dashboard já está versionado no Git
git add Eagle/eagle-infrastructure/monitoring/grafana/dashboards/infrastructure/eagle-flow-integration-dashboard.json
git commit -m "feat(monitoring): update Eagle Flow integration dashboard"
```

### Restore do Dashboard

```powershell
# Pull do Git
git pull origin main

# Reiniciar Grafana para recarregar
docker restart eagle-grafana
```

## Performance

### Otimizar Queries

Se o dashboard estiver lento:

1. Aumentar intervalo de scrape no Prometheus (de 15s para 30s)
2. Reduzir retention time (de 30d para 15d)
3. Usar recording rules para queries complexas

Exemplo de recording rule em `recording_rules.yml`:

```yaml
groups:
  - name: eagle_flow_integration_recording
    interval: 30s
    rules:
      - record: eagle_flow:integration_success_rate
        expr: |
          sum(rate(eagle_flow_integration_calls_total{status="success"}[5m])) by (service)
          / sum(rate(eagle_flow_integration_calls_total[5m])) by (service) * 100
```

## Documentação Adicional

- **Dashboard README**: `Eagle/eagle-infrastructure/monitoring/grafana/dashboards/infrastructure/EAGLE_FLOW_INTEGRATION_DASHBOARD_README.md`
- **Prometheus Config**: `Eagle/eagle-infrastructure/monitoring/prometheus.yml`
- **Grafana Provisioning**: `Eagle/eagle-infrastructure/monitoring/grafana/provisioning/`
- **Alert Rules**: `Eagle/eagle-infrastructure/monitoring/alert_rules.yml`

## Suporte

Para problemas:
1. Verificar logs: `docker logs eagle-grafana`
2. Verificar Prometheus targets: http://localhost:9090/targets
3. Verificar métricas do Eagle Flow: http://localhost:8092/actuator/prometheus
4. Consultar documentação completa no README do dashboard
