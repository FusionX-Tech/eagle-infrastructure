#!/bin/bash

# Istio Service Mesh Setup Script
# Este script configura o Istio Service Mesh para o sistema de criação de alertas

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
    
    # Verificar istioctl
    if ! command -v istioctl &> /dev/null; then
        log_warning "istioctl não encontrado. Instalando..."
        install_istioctl
    fi
    
    # Verificar conexão com cluster
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Não foi possível conectar ao cluster Kubernetes."
        exit 1
    fi
    
    log_success "Pré-requisitos verificados com sucesso!"
}

# Instalar istioctl
install_istioctl() {
    log_info "Instalando istioctl..."
    
    # Download e instalação do Istio
    curl -L https://istio.io/downloadIstio | sh -
    
    # Adicionar ao PATH (temporariamente)
    export PATH="$PWD/istio-*/bin:$PATH"
    
    # Verificar instalação
    if istioctl version --remote=false; then
        log_success "istioctl instalado com sucesso!"
    else
        log_error "Falha na instalação do istioctl"
        exit 1
    fi
}

# Instalar Istio no cluster
install_istio() {
    log_info "Instalando Istio no cluster..."
    
    # Instalar Istio com configuração de produção
    istioctl install --set values.defaultRevision=default \
                     --set values.pilot.traceSampling=1.0 \
                     --set values.global.meshConfig.accessLogFile=/dev/stdout \
                     --set values.global.meshConfig.defaultConfig.proxyStatsMatcher.inclusionRegexps=".*outlier_detection.*" \
                     --set values.global.meshConfig.defaultConfig.proxyStatsMatcher.exclusionRegexps=".*osconfig.*" \
                     -y
    
    if [ $? -eq 0 ]; then
        log_success "Istio instalado com sucesso!"
    else
        log_error "Falha na instalação do Istio"
        exit 1
    fi
}

# Configurar namespaces
setup_namespaces() {
    log_info "Configurando namespaces..."
    
    # Aplicar configurações de namespace
    kubectl apply -f namespace/
    
    # Habilitar injeção automática de sidecar
    kubectl label namespace eagle-services istio-injection=enabled --overwrite
    kubectl label namespace default istio-injection=enabled --overwrite
    
    log_success "Namespaces configurados com sucesso!"
}

# Aplicar políticas de segurança
apply_security_policies() {
    log_info "Aplicando políticas de segurança..."
    
    # Aguardar Istio estar pronto
    kubectl wait --for=condition=available --timeout=300s deployment/istiod -n istio-system
    
    # Aplicar políticas de segurança
    kubectl apply -f security/
    
    log_success "Políticas de segurança aplicadas!"
}

# Configurar traffic management
setup_traffic_management() {
    log_info "Configurando traffic management..."
    
    # Aplicar configurações de tráfego
    kubectl apply -f traffic-management/
    
    log_success "Traffic management configurado!"
}

# Configurar observabilidade
setup_observability() {
    log_info "Configurando observabilidade..."
    
    # Instalar addons de observabilidade
    kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/prometheus.yaml
    kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/grafana.yaml
    kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/jaeger.yaml
    kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/kiali.yaml
    
    # Aplicar configurações customizadas
    kubectl apply -f observability/
    
    log_success "Observabilidade configurada!"
}

# Aplicar configurações de deployment
apply_deployment_configs() {
    log_info "Aplicando configurações de deployment..."
    
    kubectl apply -f deployment/
    
    log_success "Configurações de deployment aplicadas!"
}

# Verificar instalação
verify_installation() {
    log_info "Verificando instalação..."
    
    # Verificar Istio
    if istioctl verify-install; then
        log_success "Istio verificado com sucesso!"
    else
        log_warning "Verificação do Istio apresentou problemas"
    fi
    
    # Verificar pods do sistema
    log_info "Verificando pods do sistema Istio..."
    kubectl get pods -n istio-system
    
    # Verificar injeção de sidecars
    log_info "Verificando injeção de sidecars..."
    kubectl get pods -n eagle-services -o wide
    
    # Verificar políticas de segurança
    log_info "Verificando políticas de segurança..."
    kubectl get peerauthentication -n eagle-services
    kubectl get authorizationpolicy -n eagle-services
}

# Mostrar informações de acesso
show_access_info() {
    log_info "Informações de acesso aos dashboards:"
    
    echo ""
    echo "Para acessar os dashboards, execute os comandos abaixo em terminais separados:"
    echo ""
    echo "Grafana (métricas):"
    echo "  kubectl port-forward -n istio-system svc/grafana 3000:3000"
    echo "  Acesse: http://localhost:3000"
    echo ""
    echo "Jaeger (tracing):"
    echo "  kubectl port-forward -n istio-system svc/jaeger 16686:16686"
    echo "  Acesse: http://localhost:16686"
    echo ""
    echo "Kiali (service mesh dashboard):"
    echo "  kubectl port-forward -n istio-system svc/kiali 20001:20001"
    echo "  Acesse: http://localhost:20001"
    echo ""
    echo "Prometheus (métricas raw):"
    echo "  kubectl port-forward -n istio-system svc/prometheus 9090:9090"
    echo "  Acesse: http://localhost:9090"
}

# Função principal
main() {
    echo "🚀 Iniciando setup do Istio Service Mesh..."
    echo "================================================"
    
    check_prerequisites
    install_istio
    setup_namespaces
    apply_security_policies
    setup_traffic_management
    setup_observability
    apply_deployment_configs
    verify_installation
    
    echo ""
    echo "================================================"
    log_success "🎉 Istio Service Mesh configurado com sucesso!"
    echo "================================================"
    
    show_access_info
}

# Executar função principal
main "$@"