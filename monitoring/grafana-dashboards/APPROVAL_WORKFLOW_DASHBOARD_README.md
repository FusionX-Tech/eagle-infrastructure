# Approval Workflow Dashboard - Grafana

## Overview

Este dashboard fornece monitoramento completo do sistema de aprovação de regras do Eagle, incluindo métricas de workflows, emails, tokens e alertas.

## Dashboard File

- **File**: `approval-workflow-dashboard.json`
- **UID**: `approval-workflow`
- **Title**: Approval Workflow - Monitoring Dashboard

## Panels Overview

### 1. Workflow Status Overview (Row 1)
- **Pending Workflows**: Gauge mostrando workflows pendentes (threshold: 100)
- **Workflows Created**: Total de workflows criados nas últimas 24h
- **Workflows Approved**: Total de workflows aprovados nas últimas 24h
- **Workflows Rejected**: Total de workflows rejeitados nas últimas 24h

### 2. Workflow Rates (Row 2)
- **Workflow Creation Rate**: Taxa de criação de workflows por tipo (CREATE, UPDATE, DELETE)
- **Approval vs Rejection Rate**: Comparação entre aprovações, rejeições e cancelamentos

### 3. Approval Performance (Row 3)
- **Average Approval Time**: Percentis p50, p95, p99 do tempo de aprovação
  - Threshold: 24 horas (linha vermelha)
- **Rejection Rate (%)**: Percentual de workflows rejeitados
  - Alert: > 50% (crítico)

### 4. Email Service Monitoring (Row 4)
- **Email Service Status**: UP/DOWN status do serviço SMTP
- **Emails Sent**: Total de emails enviados nas últimas 24h
- **Email Failures**: Total de falhas no envio de emails
  - Thresholds: 0-10 (green), 10-50 (yellow), >50 (red)

### 5. Email Performance (Row 5)
- **Email Send Rate**: Taxa de envio de emails por tipo
- **Email Failure Rate (%)**: Percentual de falhas no envio
  - Alert: > 5% (crítico)

### 6. Token Management (Row 6)
- **Token Generation Rate**: Taxa de geração e validação de tokens
- **Token Expiration Rate**: Taxa de expiração de tokens
  - Threshold: 10 tokens/hora (crítico)

### 7. Security & Errors (Row 7)
- **Invalid Token Attempts**: Tentativas de uso de tokens inválidos
  - Alert: > 5 tentativas/sec (possível ataque)
- **Approval Errors**: Erros de aprovação (duplicadas, self-approval, aprovador inativo)

### 8. Business Metrics (Row 8)
- **Workflow Distribution by Type**: Distribuição de workflows por tipo (pie chart)
- **Approval Rate by Type**: Taxa de aprovação por tipo (bar gauge)
- **Active Alerts**: Tabela de alertas ativos do sistema

## Metrics Used

### Workflow Metrics
- `approval_workflow_pending_gauge`: Workflows pendentes (gauge)
- `approval_workflow_created_total`: Total de workflows criados (counter)
- `approval_workflow_approved_total`: Total de workflows aprovados (counter)
- `approval_workflow_rejected_total`: Total de workflows rejeitados (counter)
- `approval_workflow_cancelled_total`: Total de workflows cancelados (counter)
- `approval_workflow_duration_seconds`: Duração dos workflows (histogram)

### Email Metrics
- `approval_email_sent_total`: Total de emails enviados (counter)
- `approval_email_failed_total`: Total de falhas no envio (counter)
- `up{health_component="emailService"}`: Status do serviço de email

### Token Metrics
- `approval_token_generated_total`: Total de tokens gerados (counter)
- `approval_token_validated_total`: Total de tokens validados (counter)
- `approval_token_expired_total`: Total de tokens expirados (counter)
- `approval_token_invalid_total`: Total de tokens inválidos (counter)

### Error Metrics
- `approval_duplicate_attempt_total`: Tentativas de aprovação duplicada (counter)
- `approval_self_approval_attempt_total`: Tentativas de auto-aprovação (counter)
- `approval_inactive_approver_attempt_total`: Tentativas de aprovador inativo (counter)

## Alerts Integration

O dashboard está integrado com os alertas do Prometheus definidos em `prometheus/rules/approval-workflow-alerts.yml`:

- **TooManyPendingWorkflows**: > 100 workflows pendentes
- **HighWorkflowRejectionRate**: > 50% de rejeição
- **EmailServiceDown**: Serviço SMTP indisponível
- **HighTokenExpirationRate**: > 10 tokens expirando por hora
- **InvalidTokenUsage**: > 5 tentativas de tokens inválidos/sec

## Installation

### 1. Via Grafana UI

1. Acesse Grafana: `http://localhost:3000`
2. Login: admin/admin
3. Navegue para: Dashboards → Import
4. Upload do arquivo: `approval-workflow-dashboard.json`
5. Selecione datasource: Prometheus
6. Click em "Import"

### 2. Via Provisioning (Automático)

O dashboard é automaticamente provisionado quando o Grafana inicia, através da configuração em:
```
grafana/provisioning/dashboards/dashboards.yml
```

## Variables

### Datasource
- **Name**: `datasource`
- **Type**: datasource
- **Query**: prometheus
- **Default**: Prometheus

### Workflow Type
- **Name**: `workflow_type`
- **Type**: query
- **Query**: `label_values(approval_workflow_created_total, type)`
- **Options**: CREATE, UPDATE, DELETE, All
- **Multi-select**: Yes

## Refresh Rate

- **Default**: 30 seconds
- **Options**: 5s, 10s, 30s, 1m, 5m, 15m, 30m, 1h

## Time Range

- **Default**: Last 6 hours
- **Recommended**: 
  - Real-time monitoring: Last 1 hour
  - Daily review: Last 24 hours
  - Weekly analysis: Last 7 days

## Thresholds & SLAs

### Workflow SLAs
- **Pending Workflows**: < 100 (healthy), > 100 (critical)
- **Approval Time**: < 24 hours (target)
- **Rejection Rate**: < 30% (healthy), > 50% (critical)

### Email SLAs
- **Email Failure Rate**: < 5% (healthy), > 5% (critical)
- **Email Service Uptime**: > 99.9%

### Token SLAs
- **Token Expiration Rate**: < 10/hour (healthy), > 10/hour (warning)
- **Invalid Token Rate**: < 5/sec (healthy), > 5/sec (critical - possible attack)

## Troubleshooting

### Dashboard Not Loading
1. Verify Prometheus datasource is configured
2. Check Prometheus is scraping ms-rules metrics
3. Verify metrics endpoint: `http://localhost:8080/actuator/prometheus`

### No Data in Panels
1. Check if ms-rules service is running
2. Verify metrics are being exposed: `curl http://localhost:8080/actuator/prometheus | grep approval`
3. Check Prometheus targets: `http://localhost:9090/targets`

### Alerts Not Showing
1. Verify alert rules are loaded in Prometheus
2. Check Prometheus rules: `http://localhost:9090/rules`
3. Verify Alertmanager is configured

## Maintenance

### Regular Tasks
- Review dashboard weekly for performance trends
- Update thresholds based on actual usage patterns
- Add new panels for additional metrics as needed
- Export updated dashboard JSON after changes

### Backup
```bash
# Export dashboard via API
curl -H "Authorization: Bearer <api-key>" \
  http://localhost:3000/api/dashboards/uid/approval-workflow \
  > approval-workflow-dashboard-backup.json
```

## Related Documentation

- [Prometheus Alert Rules](../prometheus/rules/approval-workflow-alerts.yml)
- [Health Indicators](../../services/ms-rules/src/main/java/pro/fusionx/eagle/rules/infrastructure/health/)
- [Approval Workflow Design](../../services/ms-rules/.kiro/specs/ms-rules-approval/design.md)

## Support

For issues or questions:
- Team: Eagle Platform Team
- Component: Approval Workflow
- Slack: #eagle-monitoring
