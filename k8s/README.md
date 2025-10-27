# Kubernetes Deployment - Sistema de Criação de Alertas

Este diretório contém todas as configurações Kubernetes para deploy do sistema de criação de alertas em ambiente cloud-native.

## Estrutura de Arquivos

```
k8s/
├── README.md                    # Este arquivo
├── namespace/                   # Configurações de namespace
│   ├── eagle-services.yaml     # Namespace principal dos microserviços
│   └── resource-quotas.yaml    # Quotas de recursos por namespace
├── configmaps/                  # ConfigMaps para configurações
│   ├── app-config.yaml         # Configurações gerais da aplicação
│   ├── database-config.yaml    # Configurações de banco de dados
│   └── sqs-config.yaml         # Configurações SQS
├── secrets/                     # Secrets para dados sensíveis
│   ├── database-secrets.yaml   # Credenciais de banco
│   ├── keycloak-secrets.yaml   # Credenciais Keycloak
│   └── vault-secrets.yaml      # Configurações Vault
├── deployments/                 # Deployments dos microserviços
│   ├── ms-orchestrator.yaml    # MS-Orchestrator deployment
│   ├── ms-alert.yaml           # MS-Alert deployment
│   ├── ms-customer.yaml        # MS-Customer deployment
│   ├── ms-transaction.yaml     # MS-Transaction deployment
│   ├── ms-api.yaml             # MS-API deployment
│   └── ms-enrichment.yaml      # MS-Enrichment deployment
├── services/                    # Services para exposição
│   ├── ms-orchestrator-svc.yaml
│   ├── ms-alert-svc.yaml
│   ├── ms-customer-svc.yaml
│   ├── ms-transaction-svc.yaml
│   ├── ms-api-svc.yaml
│   └── ms-enrichment-svc.yaml
├── hpa/                        # Horizontal Pod Autoscaling
│   ├── ms-orchestrator-hpa.yaml
│   ├── ms-alert-hpa.yaml
│   ├── ms-customer-hpa.yaml
│   ├── ms-transaction-hpa.yaml
│   ├── ms-api-hpa.yaml
│   └── ms-enrichment-hpa.yaml
├── vpa/                        # Vertical Pod Autoscaling
│   └── vpa-configs.yaml
├── pdb/                        # Pod Disruption Budgets
│   └── pod-disruption-budgets.yaml
├── ingress/                    # Ingress configurations
│   └── api-gateway-ingress.yaml
└── monitoring/                 # Monitoring configurations
    ├── service-monitors.yaml   # Prometheus ServiceMonitors
    └── pod-monitors.yaml       # Prometheus PodMonitors
```

## Pré-requisitos

1. **Kubernetes cluster** (versão 1.24+)
2. **Istio Service Mesh** instalado
3. **Prometheus Operator** para métricas
4. **Metrics Server** para HPA
5. **Vertical Pod Autoscaler** (opcional)

## Deployment

### 1. Aplicar Configurações Base

```bash
# Namespace e quotas
kubectl apply -f namespace/

# ConfigMaps e Secrets
kubectl apply -f configmaps/
kubectl apply -f secrets/

# Services
kubectl apply -f services/
```

### 2. Deploy dos Microserviços

```bash
# Deployments
kubectl apply -f deployments/

# Verificar status
kubectl get pods -n eagle-services -w
```

### 3. Configurar Auto-scaling

```bash
# Horizontal Pod Autoscaling
kubectl apply -f hpa/

# Vertical Pod Autoscaling (opcional)
kubectl apply -f vpa/

# Pod Disruption Budgets
kubectl apply -f pdb/
```

### 4. Configurar Ingress e Monitoring

```bash
# Ingress
kubectl apply -f ingress/

# Monitoring
kubectl apply -f monitoring/
```

## Configurações de Recursos

### Requests e Limits

Cada microserviço tem configurações específicas baseadas no perfil de uso:

- **MS-Orchestrator**: CPU intensivo para orquestração
- **MS-Alert**: Balanceado para CRUD operations
- **MS-Customer**: Memory intensivo para cache
- **MS-Transaction**: CPU intensivo para analytics
- **MS-API**: Network intensivo para APIs externas
- **MS-Enrichment**: CPU intensivo para processamento paralelo

### Auto-scaling

- **HPA**: Baseado em CPU, memória e métricas customizadas (SQS queue depth)
- **VPA**: Recomendações automáticas de recursos
- **Cluster Autoscaler**: Scaling automático de nós (configurado no cluster)

## Health Checks

Todos os microserviços implementam:

- **Liveness Probe**: `/actuator/health/liveness`
- **Readiness Probe**: `/actuator/health/readiness`
- **Startup Probe**: `/actuator/health` (para inicialização lenta)

## Segurança

- **Service Accounts**: Contas específicas para cada microserviço
- **RBAC**: Permissões mínimas necessárias
- **Network Policies**: Isolamento de rede (via Istio)
- **Pod Security Standards**: Enforced no namespace

## Monitoramento

- **Prometheus**: Coleta automática de métricas
- **ServiceMonitor**: Configuração para descoberta automática
- **Alerting**: Alertas baseados em SLIs/SLOs

## Troubleshooting

### Comandos Úteis

```bash
# Status geral
kubectl get all -n eagle-services

# Logs de um microserviço
kubectl logs -n eagle-services deployment/ms-alert -f

# Describe de um pod com problemas
kubectl describe pod -n eagle-services <pod-name>

# Verificar HPA
kubectl get hpa -n eagle-services

# Verificar métricas
kubectl top pods -n eagle-services
```

### Problemas Comuns

1. **Pod não inicia**: Verificar resources, secrets e configmaps
2. **HPA não funciona**: Verificar metrics-server e resource requests
3. **Conectividade**: Verificar services e network policies
4. **Performance**: Verificar resource limits e HPA configuration