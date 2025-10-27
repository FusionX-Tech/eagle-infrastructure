# Istio Service Mesh Implementation

Este diretório contém as configurações do Istio Service Mesh para o sistema de criação de alertas.

## Visão Geral

O Istio Service Mesh fornece:
- **mTLS automático** entre todos os microserviços
- **Traffic management** com load balancing inteligente
- **Security policies** com controle de acesso granular
- **Observabilidade** com métricas, logs e tracing distribuído
- **Resilience** com circuit breakers, timeouts e retry policies

## Estrutura de Arquivos

```
istio/
├── README.md                    # Este arquivo
├── setup-istio.sh              # Script de instalação do Istio
├── namespace/                  # Configurações de namespace
│   ├── eagle-services.yaml     # Namespace principal dos microserviços
│   └── istio-system.yaml       # Namespace do Istio
├── security/                   # Políticas de segurança
│   ├── peer-authentication.yaml # Configuração mTLS
│   ├── authorization-policies.yaml # Controle de acesso
│   └── network-policies.yaml   # Isolamento de rede
├── traffic-management/         # Gerenciamento de tráfego
│   ├── virtual-services.yaml   # Roteamento de tráfego
│   ├── destination-rules.yaml  # Políticas de load balancing
│   └── gateways.yaml          # Ingress gateway
├── observability/             # Monitoramento e observabilidade
│   ├── telemetry.yaml         # Configuração de telemetria
│   ├── jaeger.yaml            # Distributed tracing
│   └── prometheus.yaml        # Métricas
└── deployment/                # Configurações de deployment
    ├── service-entries.yaml   # Serviços externos
    └── sidecars.yaml          # Configuração de sidecars
```

## Pré-requisitos

1. **Kubernetes cluster** (local com Kind ou produção)
2. **Istioctl** instalado
3. **Kubectl** configurado
4. **Helm** (opcional, para componentes adicionais)

## Instalação

### 1. Instalar Istio

```bash
# Executar o script de setup
./setup-istio.sh

# Ou manualmente:
istioctl install --set values.defaultRevision=default -y
kubectl label namespace eagle-services istio-injection=enabled
```

### 2. Aplicar Configurações

```bash
# Aplicar todas as configurações
kubectl apply -f namespace/
kubectl apply -f security/
kubectl apply -f traffic-management/
kubectl apply -f observability/
kubectl apply -f deployment/
```

### 3. Verificar Instalação

```bash
# Verificar status do Istio
istioctl verify-install

# Verificar injeção de sidecars
kubectl get pods -n eagle-services -o wide

# Verificar políticas de segurança
istioctl authn tls-check ms-alert.eagle-services.svc.cluster.local
```

## Configurações de Segurança

### mTLS (Mutual TLS)

- **Modo STRICT**: Todas as comunicações entre microserviços são criptografadas
- **Certificados automáticos**: Istio gerencia automaticamente os certificados
- **Rotação automática**: Certificados são rotacionados automaticamente

### Authorization Policies

- **Princípio do menor privilégio**: Cada microserviço só pode acessar o que precisa
- **Controle baseado em identidade**: Usando service accounts do Kubernetes
- **Validação de JWT**: Tokens Keycloak são validados no mesh

## Traffic Management

### Load Balancing

- **Round Robin**: Distribuição uniforme de requisições
- **Least Connections**: Roteamento para instâncias com menos conexões
- **Health Checks**: Remoção automática de instâncias não saudáveis

### Circuit Breakers

- **Timeout**: 30s para operações externas, 10s para internas
- **Retry**: 3 tentativas com backoff exponencial
- **Outlier Detection**: Remoção temporária de instâncias com falhas

## Observabilidade

### Métricas

- **Prometheus**: Coleta automática de métricas de tráfego
- **Grafana**: Dashboards pré-configurados para Istio
- **Custom Metrics**: Métricas específicas do negócio

### Tracing

- **Jaeger**: Tracing distribuído automático
- **Correlation IDs**: Rastreamento de requisições end-to-end
- **Performance Analysis**: Identificação de gargalos

### Logs

- **Access Logs**: Logs de acesso automáticos
- **Structured Logging**: Logs estruturados em JSON
- **Centralized Collection**: Coleta centralizada com Fluentd/Fluent Bit

## Desenvolvimento Local

### Docker Compose + Istio

Para desenvolvimento local, use o Kind (Kubernetes in Docker):

```bash
# Criar cluster Kind com Istio
kind create cluster --config=kind-config.yaml

# Instalar Istio
./setup-istio.sh

# Deploy dos microserviços
kubectl apply -f ../k8s/
```

### Testes de Conectividade

```bash
# Testar mTLS entre serviços
kubectl exec -n eagle-services deployment/ms-alert -- curl -v ms-customer:8085/actuator/health

# Verificar certificados
istioctl proxy-config secret ms-alert-xxx -n eagle-services

# Analisar tráfego
istioctl proxy-config cluster ms-alert-xxx -n eagle-services
```

## Troubleshooting

### Problemas Comuns

1. **Sidecar não injetado**
   ```bash
   kubectl label namespace eagle-services istio-injection=enabled
   kubectl rollout restart deployment -n eagle-services
   ```

2. **mTLS falhando**
   ```bash
   istioctl authn tls-check ms-alert.eagle-services.svc.cluster.local
   kubectl logs -n eagle-services deployment/ms-alert -c istio-proxy
   ```

3. **Políticas de autorização muito restritivas**
   ```bash
   kubectl get authorizationpolicy -n eagle-services
   kubectl describe authorizationpolicy allow-ms-alert -n eagle-services
   ```

### Comandos Úteis

```bash
# Status geral do Istio
istioctl analyze -n eagle-services

# Configuração do proxy
istioctl proxy-config all ms-alert-xxx.eagle-services

# Logs do sidecar
kubectl logs -n eagle-services ms-alert-xxx -c istio-proxy

# Métricas do Envoy
kubectl exec -n eagle-services ms-alert-xxx -c istio-proxy -- curl localhost:15000/stats
```

## Migração Gradual

### Fase 1: Instalação Base
- [x] Instalar Istio no cluster
- [x] Configurar namespace com injeção automática
- [x] Aplicar políticas básicas de segurança

### Fase 2: mTLS
- [x] Habilitar mTLS em modo permissivo
- [x] Verificar conectividade entre serviços
- [x] Migrar para modo STRICT

### Fase 3: Traffic Management
- [x] Configurar Virtual Services
- [x] Implementar Destination Rules
- [x] Configurar circuit breakers

### Fase 4: Observabilidade
- [ ] Configurar Jaeger para tracing
- [ ] Implementar dashboards Grafana
- [ ] Configurar alertas Prometheus

## Referências

- [Istio Documentation](https://istio.io/latest/docs/)
- [Istio Security Best Practices](https://istio.io/latest/docs/ops/best-practices/security/)
- [Istio Traffic Management](https://istio.io/latest/docs/concepts/traffic-management/)
- [Istio Observability](https://istio.io/latest/docs/concepts/observability/)