#!/bin/bash

# Deploy Eagle Alert System to Kubernetes with Istio
# Este script faz o deploy completo do sistema no Kubernetes

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Funções auxiliares
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Verificar pré-requisitos
check_prerequisites() {
    log_info "Verificando pré-requisitos..."
    
    # Verificar kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl não encontrado. Instale o kubectl primeiro."
        exit 1
    fi
    
    # Verificar conexão com cluster
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Não foi possível conectar ao cluster Kubernetes."
        exit 1
    fi
    
    # Verificar se Istio está instalado
    if ! kubectl get namespace istio-system &> /dev/null; then
        log_warning "Istio não está instalado. Execute ./setup-istio.sh primeiro."
        read -p "Deseja instalar o Istio agora? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            ./setup-istio.sh
        else
            exit 1
        fi
    fi
    
    log_success "Pré-requisitos verificados!"
}

# Criar secrets necessários
create_secrets() {
    log_info "Criando secrets..."
    
    # Secret para PostgreSQL
    kubectl create secret generic postgres-secret \
        --from-literal=username=eagle_user \
        --from-literal=password=eagle_password \
        --from-literal=database=eagle_db \
        --namespace=eagle-services \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # Secret para Redis
    kubectl create secret generic redis-secret \
        --from-literal=password=redis_password \
        --namespace=eagle-services \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # Secret para Keycloak
    kubectl create secret generic keycloak-secret \
        --from-literal=admin-username=admin \
        --from-literal=admin-password=admin123 \
        --namespace=eagle-services \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # Secret para Vault
    kubectl create secret generic vault-secret \
        --from-literal=root-token=myroot \
        --namespace=eagle-services \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # Secret para AWS (LocalStack)
    kubectl create secret generic aws-secret \
        --from-literal=access-key-id=test \
        --from-literal=secret-access-key=test \
        --from-literal=region=us-east-1 \
        --namespace=eagle-services \
        --dry-run=client -o yaml | kubectl apply -f -
    
    log_success "Secrets criados!"
}

# Criar ConfigMaps
create_configmaps() {
    log_info "Criando ConfigMaps..."
    
    # ConfigMap para configurações da aplicação
    kubectl create configmap app-config \
        --from-literal=environment=development \
        --from-literal=log-level=INFO \
        --from-literal=metrics-enabled=true \
        --namespace=eagle-services \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # ConfigMap para configurações do Istio
    kubectl create configmap istio-config \
        --from-file=../istio/ \
        --namespace=eagle-services \
        --dry-run=client -o yaml | kubectl apply -f -
    
    log_success "ConfigMaps criados!"
}

# Deploy da infraestrutura
deploy_infrastructure() {
    log_info "Fazendo deploy da infraestrutura..."
    
    # PostgreSQL
    kubectl apply -f k8s/infrastructure/postgres.yaml
    
    # Redis
    kubectl apply -f k8s/infrastructure/redis.yaml
    
    # Keycloak
    kubectl apply -f k8s/infrastructure/keycloak.yaml
    
    # Vault
    kubectl apply -f k8s/infrastructure/vault.yaml
    
    # LocalStack (SQS)
    kubectl apply -f k8s/infrastructure/localstack.yaml
    
    log_info "Aguardando infraestrutura ficar pronta..."
    kubectl wait --for=condition=available --timeout=300s deployment/postgres -n eagle-services
    kubectl wait --for=condition=available --timeout=300s deployment/redis -n eagle-services
    kubectl wait --for=condition=available --timeout=300s deployment/keycloak -n eagle-services
    kubectl wait --for=condition=available --timeout=300s deployment/vault -n eagle-services
    kubectl wait --for=condition=available --timeout=300s deployment/localstack -n eagle-services
    
    log_success "Infraestrutura deployada!"
}

# Deploy dos microserviços
deploy_microservices() {
    log_info "Fazendo deploy dos microserviços..."
    
    # MS-Customer
    kubectl apply -f k8s/microservices/ms-customer.yaml
    
    # MS-Alert
    kubectl apply -f k8s/microservices/ms-alert.yaml
    
    # MS-Transaction
    kubectl apply -f k8s/microservices/ms-transaction.yaml
    
    # MS-API
    kubectl apply -f k8s/microservices/ms-api.yaml
    
    # MS-Enrichment
    kubectl apply -f k8s/microservices/ms-enrichment.yaml
    
    # MS-Orchestrator
    kubectl apply -f k8s/microservices/ms-orchestrator.yaml
    
    log_info "Aguardando microserviços ficarem prontos..."
    kubectl wait --for=condition=available --timeout=300s deployment/ms-customer -n eagle-services
    kubectl wait --for=condition=available --timeout=300s deployment/ms-alert -n eagle-services
    kubectl wait --for=condition=available --timeout=300s deployment/ms-transaction -n eagle-services
    kubectl wait --for=condition=available --timeout=300s deployment/ms-api -n eagle-services
    kubectl wait --for=condition=available --timeout=300s deployment/ms-enrichment -n eagle-services
    kubectl wait --for=condition=available --timeout=300s deployment/ms-orchestrator -n eagle-services
    
    log_success "Microserviços deployados!"
}

# Configurar HPA (Horizontal Pod Autoscaler)
setup_hpa() {
    log_info "Configurando Horizontal Pod Autoscaler..."
    
    # Verificar se metrics-server está instalado
    if ! kubectl get deployment metrics-server -n kube-system &> /dev/null; then
        log_warning "Metrics Server não encontrado. Instalando..."
        kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
        
        # Patch para desenvolvimento local (Kind)
        kubectl patch deployment metrics-server -n kube-system --type='json' \
            -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}]'
        
        kubectl wait --for=condition=available --timeout=300s deployment/metrics-server -n kube-system
    fi
    
    # Aplicar HPAs
    kubectl apply -f k8s/hpa/
    
    log_success "HPA configurado!"
}

# Verificar deployment
verify_deployment() {
    log_info "Verificando deployment..."
    
    # Verificar pods
    echo "=== PODS ==="
    kubectl get pods -n eagle-services -o wide
    
    # Verificar services
    echo "=== SERVICES ==="
    kubectl get services -n eagle-services
    
    # Verificar Istio
    echo "=== ISTIO CONFIGURATION ==="
    kubectl get virtualservices -n eagle-services
    kubectl get destinationrules -n eagle-services
    kubectl get peerauthentication -n eagle-services
    kubectl get authorizationpolicy -n eagle-services
    
    # Verificar HPA
    echo "=== HPA ==="
    kubectl get hpa -n eagle-services
    
    # Verificar ingress
    echo "=== INGRESS ==="
    kubectl get gateway -n eagle-services
    
    # Testar conectividade
    log_info "Testando conectividade..."
    
    # Obter IP do Ingress Gateway
    INGRESS_HOST=$(kubectl get service istio-ingressgateway -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
    if [ -z "$INGRESS_HOST" ]; then
        INGRESS_HOST=$(kubectl get service istio-ingressgateway -n istio-system -o jsonpath='{.spec.clusterIP}')
    fi
    
    INGRESS_PORT=$(kubectl get service istio-ingressgateway -n istio-system -o jsonpath='{.spec.ports[?(@.name=="http2")].port}')
    
    echo "Ingress Gateway: http://$INGRESS_HOST:$INGRESS_PORT"
    
    # Testar health check
    if curl -f -s "http://$INGRESS_HOST:$INGRESS_PORT/health" > /dev/null; then
        log_success "Health check passou!"
    else
        log_warning "Health check falhou. Verifique os logs dos pods."
    fi
}

# Mostrar informações de acesso
show_access_info() {
    log_info "Informações de acesso:"
    
    echo ""
    echo "🌐 Para acessar os serviços, configure port-forwarding:"
    echo ""
    echo "API Gateway (Istio Ingress):"
    echo "  kubectl port-forward -n istio-system svc/istio-ingressgateway 8080:80"
    echo "  Acesse: http://localhost:8080"
    echo ""
    echo "Grafana (métricas):"
    echo "  kubectl port-forward -n istio-system svc/grafana 3000:3000"
    echo "  Acesse: http://localhost:3000"
    echo ""
    echo "Jaeger (tracing):"
    echo "  kubectl port-forward -n istio-system svc/jaeger-query 16686:16686"
    echo "  Acesse: http://localhost:16686"
    echo ""
    echo "Kiali (service mesh dashboard):"
    echo "  kubectl port-forward -n istio-system svc/kiali 20001:20001"
    echo "  Acesse: http://localhost:20001"
    echo ""
    echo "Prometheus (métricas):"
    echo "  kubectl port-forward -n istio-system svc/prometheus 9090:9090"
    echo "  Acesse: http://localhost:9090"
    echo ""
    echo "📊 Para monitorar o sistema:"
    echo "  kubectl get pods -n eagle-services -w"
    echo "  kubectl logs -f deployment/ms-orchestrator -n eagle-services"
    echo ""
    echo "🔍 Para debug do Istio:"
    echo "  istioctl analyze -n eagle-services"
    echo "  istioctl proxy-config cluster ms-orchestrator-xxx -n eagle-services"
}

# Função principal
main() {
    echo "🚀 Iniciando deploy do Eagle Alert System no Kubernetes..."
    echo "================================================================"
    
    check_prerequisites
    create_secrets
    create_configmaps
    deploy_infrastructure
    deploy_microservices
    setup_hpa
    verify_deployment
    
    echo ""
    echo "================================================================"
    log_success "🎉 Deploy concluído com sucesso!"
    echo "================================================================"
    
    show_access_info
}

# Executar função principal
main "$@"