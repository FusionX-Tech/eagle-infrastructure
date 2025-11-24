# Eagle Flow Integration Dashboard

## Overview

Este dashboard fornece monitoramento completo da saúde das integrações do Eagle Flow com os microserviços ms-alert, ms-customer e ms-rules. Ele rastreia métricas de sucesso, performance, resiliência (circuit breaker e retry) e erros.

## Acesso ao Dashboard

1. **URL**: http://localhost:3000 (Grafana local)
2. **Credenciais padrão**: admin/admin
3. **Localização**: Dashboards → Eagle Flow - Integration Health

## Painéis do Dashboard

### 1. Integration Success Rate by Service (Gauge)
**Métrica**: Taxa de sucesso por serviço (últimos 5 minutos)

**Interpretação**:
- 🟢 Verde (≥95%): Saúde excelente
- 🟡 Amarelo (90-95%): Atenção necessária
- 🔴 Vermelho (<90%): Problema crítico

**Ação**: Se vermelho ou amarelo, verificar logs e estado do circuit breaker

### 2-4. Success Rate por Serviço Individual (Stats)
**Métricas**: Taxa de sucesso específica para ms-alert, ms-customer e ms-rules

**Interpretação**: Permite identificar rapidamente qual serviço está com problemas

**Ação**: Focar troubleshooting no serviço com menor taxa de sucesso

### 5. Total Integration Calls (Stat)
**Métrica**: Total de chamadas de integração na última hora

**Interpretação**: Indica volume de tráfego e carga do sistema

**Ação**: Comparar com baseline esperado; picos podem indicar problemas

### 6. Response Time by Service (Graph)
**Métricas**: Percentis p50, p95 e p99 do tempo de resposta

**Interpretação**:
- p50: Tempo médio típico
- p95: 95% das requisições são mais rápidas que este valor
- p99: Detecta outliers e problemas de performance

**Thresholds**:
- 🟢 <300ms: Excelente
- 🟡 300-500ms: Aceitável
- 🔴 >500ms: Problema de performance

**Ação**: Se p95 ou p99 estão altos, investigar:
- Logs de timeout
- Carga do serviço downstream
- Problemas de rede

### 7. Average Response Time by Service (Graph)
**Métrica**: Tempo médio de resposta por serviço

**Interpretação**: Tendência geral de performance ao longo do tempo

**Ação**: Identificar degradação progressiva de performance

### 8. Circuit Breaker State (Stat)
**Métrica**: Estado atual do circuit breaker por serviço

**Estados**:
- 🟢 CLOSED (0): Normal, requisições passam
- 🟡 HALF_OPEN (1): Testando recuperação
- 🔴 OPEN (2): Circuit aberto, requisições bloqueadas

**Ação**: 
- Se OPEN: Verificar saúde do serviço downstream
- Se HALF_OPEN: Monitorar se fecha ou reabre
- Verificar logs para causa raiz

### 9. Circuit Breaker State Timeline (Graph)
**Métrica**: Histórico de mudanças de estado do circuit breaker

**Interpretação**: Visualiza quando e com que frequência o circuit abre

**Ação**: Padrões de abertura frequente indicam instabilidade do serviço

### 10. Error Rate by Service (Graph)
**Métrica**: Taxa de erro percentual por serviço

**Alert**: Dispara alerta se taxa de erro > 5%

**Interpretação**:
- 🟢 <1%: Normal
- 🟡 1-5%: Atenção
- 🔴 >5%: Crítico

**Ação**: Investigar logs de erro e causa raiz

### 11. Total Errors by Service (Graph)
**Métrica**: Contagem absoluta de erros por serviço

**Interpretação**: Volume total de falhas (não percentual)

**Ação**: Correlacionar com eventos de deploy ou mudanças de infraestrutura

### 12. Retry Attempts by Service (Graph)
**Métrica**: Taxa de tentativas de retry por segundo

**Interpretação**:
- Alto volume de retries indica problemas temporários
- Retries bem-sucedidos melhoram resiliência
- Retries excessivos podem indicar problema persistente

**Ação**: Se retries são altos mas sucesso é baixo, problema não é temporário

### 13-15. Total Retry Attempts (Stats)
**Métrica**: Total de retries na última hora por serviço

**Interpretação**: Volume absoluto de retries

**Ação**: Comparar com baseline; aumento súbito indica instabilidade

### 16. Integration Calls Rate (Graph)
**Métrica**: Taxa de chamadas por segundo, empilhadas por status (success/failure)

**Interpretação**: Visualiza proporção de sucesso vs falha ao longo do tempo

**Ação**: Identificar períodos de alta taxa de falha

### 17. Success vs Failure Ratio (Pie Chart)
**Métrica**: Proporção de sucesso vs falha na última hora

**Interpretação**: Visão geral rápida da saúde das integrações

**Ação**: Se fatia vermelha (failure) é significativa, investigar

### 18. Integration Health Summary (Table)
**Métricas consolidadas**:
- Success Rate (%)
- P95 Response Time (s)
- Total Calls (1h)
- Retry Attempts (1h)
- Circuit Breaker State

**Interpretação**: Visão tabular completa de todas as métricas por serviço

**Ação**: Use para comparação rápida entre serviços e identificação de problemas

## Variáveis do Dashboard

### datasource
Fonte de dados Prometheus (geralmente "Prometheus")

### service
Filtro multi-seleção para focar em serviços específicos:
- All: Mostra todos os serviços
- ms-alert: Apenas ms-alert
- ms-customer: Apenas ms-customer
- ms-rules: Apenas ms-rules

## Anotações

### Deployments
Marca no gráfico quando ocorre deploy (mudança na versão)

**Uso**: Correlacionar problemas com deploys recentes

### Circuit Breaker Opens
Marca quando um circuit breaker abre

**Uso**: Identificar eventos de falha crítica

## Alertas Configurados

### High Integration Error Rate
**Condição**: Taxa de erro > 5% por 5 minutos

**Ação**: 
1. Verificar qual serviço está falhando
2. Checar logs do Eagle Flow e do serviço downstream
3. Verificar estado do circuit breaker
4. Validar conectividade de rede

## Troubleshooting com o Dashboard

### Cenário 1: Taxa de Sucesso Baixa
1. Verificar painel "Circuit Breaker State" → Se OPEN, serviço está down
2. Verificar painel "Error Rate" → Identificar qual serviço
3. Verificar painel "Retry Attempts" → Se alto, problema temporário
4. Ação: Verificar logs e saúde do serviço downstream

### Cenário 2: Response Time Alto
1. Verificar painel "Response Time by Service" → Identificar qual serviço
2. Verificar painel "Integration Calls Rate" → Se carga está alta
3. Ação: 
   - Verificar carga do serviço downstream
   - Verificar timeouts configurados
   - Considerar escalar serviço

### Cenário 3: Circuit Breaker Abrindo Frequentemente
1. Verificar painel "Circuit Breaker State Timeline" → Frequência de aberturas
2. Verificar painel "Error Rate" → Causa das falhas
3. Ação:
   - Ajustar thresholds do circuit breaker se necessário
   - Resolver problema raiz no serviço downstream
   - Verificar configuração de retry

### Cenário 4: Retries Excessivos
1. Verificar painel "Retry Attempts by Service" → Volume de retries
2. Verificar painel "Success Rate" → Se retries estão ajudando
3. Ação:
   - Se retries não melhoram sucesso, problema não é temporário
   - Verificar configuração de retry (max attempts, wait duration)
   - Resolver problema raiz

## Queries Prometheus Úteis

### Taxa de Sucesso
```promql
sum(rate(eagle_flow_integration_calls_total{status="success"}[5m])) by (service) 
/ sum(rate(eagle_flow_integration_calls_total[5m])) by (service) * 100
```

### P95 Response Time
```promql
histogram_quantile(0.95, 
  sum(rate(eagle_flow_integration_duration_seconds_bucket[5m])) by (service, le)
)
```

### Circuit Breaker State
```promql
eagle_flow_circuit_breaker_state
```

### Total Retries
```promql
sum(increase(eagle_flow_retry_attempts_total[1h])) by (service)
```

## Integração com Alertmanager

Para configurar alertas via Alertmanager, adicione em `alert_rules.yml`:

```yaml
groups:
  - name: eagle_flow_integration
    interval: 1m
    rules:
      - alert: HighIntegrationErrorRate
        expr: |
          sum(rate(eagle_flow_integration_calls_total{status="failure"}[5m])) by (service)
          / sum(rate(eagle_flow_integration_calls_total[5m])) by (service) * 100 > 5
        for: 5m
        labels:
          severity: critical
          component: eagle-flow
        annotations:
          summary: "High error rate on {{ $labels.service }}"
          description: "Error rate is {{ $value }}% on {{ $labels.service }}"

      - alert: CircuitBreakerOpen
        expr: eagle_flow_circuit_breaker_state == 2
        for: 2m
        labels:
          severity: warning
          component: eagle-flow
        annotations:
          summary: "Circuit breaker open for {{ $labels.service }}"
          description: "Circuit breaker has been open for 2 minutes"

      - alert: HighResponseTime
        expr: |
          histogram_quantile(0.95,
            sum(rate(eagle_flow_integration_duration_seconds_bucket[5m])) by (service, le)
          ) > 0.5
        for: 5m
        labels:
          severity: warning
          component: eagle-flow
        annotations:
          summary: "High response time on {{ $labels.service }}"
          description: "P95 response time is {{ $value }}s on {{ $labels.service }}"

      - alert: ExcessiveRetries
        expr: sum(rate(eagle_flow_retry_attempts_total[5m])) by (service) > 1
        for: 10m
        labels:
          severity: warning
          component: eagle-flow
        annotations:
          summary: "Excessive retries on {{ $labels.service }}"
          description: "Retry rate is {{ $value }}/s on {{ $labels.service }}"
```

## Manutenção do Dashboard

### Atualização
1. Editar arquivo `eagle-flow-integration-dashboard.json`
2. Reimportar no Grafana ou reiniciar stack de monitoring

### Backup
Dashboard é versionado no Git em:
```
Eagle/eagle-infrastructure/monitoring/grafana-dashboards/eagle-flow-integration-dashboard.json
```

### Customização
Para adicionar novos painéis:
1. Editar dashboard no Grafana UI
2. Exportar JSON
3. Salvar no arquivo versionado
4. Commit no Git

## Referências

- **Métricas**: Implementadas em `ResilientRestClient.java`
- **Requirements**: 8.1, 8.2, 8.3, 8.4, 8.5
- **Design**: `.kiro/specs/eagle-flow-alert-creation-fix/design.md`
- **Grafana Docs**: https://grafana.com/docs/
- **Prometheus Docs**: https://prometheus.io/docs/

## Suporte

Para problemas com o dashboard:
1. Verificar se Prometheus está coletando métricas: http://localhost:9090
2. Verificar se Eagle Flow está expondo métricas: http://localhost:8092/actuator/prometheus
3. Verificar logs do Grafana
4. Validar queries Prometheus diretamente no Prometheus UI
