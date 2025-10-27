#!/bin/bash

# Script de validação da configuração do Istio
# Verifica se todas as configurações estão corretas e funcionando

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Contadores
TESTS_PASSED=0
TESTS_FAILED=0
TOTAL_TESTS=0

# Funções auxiliares
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    ((TESTS_PASSED++))
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    ((TESTS_FAILED++))
}

test_start() {
    ((TOTAL_TESTS++))
    log_info "Teste $TOTAL_TESTS: $1"
}

# Verificar instalação do Istio
test_istio_installation() {
    test_start "Verificando instalação do Istio"
    
    if kubectl get namespace istio-system &> /dev/null; then
        if kubectl get deployment istiod -n istio-system &> /dev/null; then
            if kubectl get pods -n istio-system -l app=istiod --field-selector=status.phase=Running | grep -q istiod; then
                log_success "Istio está instalado e rodando"
            else
                log_error "Istio está instalado mas não está rodando"
            fi
        else
            log_error "Deployment istiod não encontrado"
        fi
    else
        log_error "Namespace istio-system não encontrado"
    fi
}

# Verificar namespace eagle-services
test_namespace_configuration() {
    test_start "Verificando configuração do namespace eagle-services"
    
    if kubectl get namespace eagle-services &> /dev/null; then
        # Verificar se injeção automática está habilitada
        INJECTION_LABEL=$(kubectl get namespace eagle-services -o jsonpath='{.metadata.labels.istio-injection}')
        if [ "$INJECTION_LABEL" = "enabled" ]; then
            log_success "Namespace eagle-services configurado com injeção automática"
        else
            log_error "Injeção automática não está habilitada no namespace eagle-services"
        fi
    else
        log_error "Namespace eagle-services não encontrado"
    fi
}

# Verificar injeção de sidecars
test_sidecar_injection() {
    test_start "Verificando injeção de sidecars"
    
    # Verificar se existem pods no namespace
    PODS=$(kubectl get pods -n eagle-services --no-headers 2>/dev/null | wc -l)
    if [ "$PODS" -gt 0 ]; then
        # Verificar se pods têm sidecars
        PODS_WITH_SIDECARS=$(kubectl get pods -n eagle-services -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.containers[*].name}{"\n"}{end}' | grep istio-proxy | wc -l)
        
        if [ "$PODS_WITH_SIDECARS" -gt 0 ]; then
            log_success "Sidecars injetados em $PODS_WITH_SIDECARS pods"
        else
            log_error "Nenhum sidecar encontrado nos pods"
        fi
    else
        log_warning "Nenhum pod encontrado no namespace eagle-services"
    fi
}

# Verificar políticas de segurança
test_security_policies() {
    test_start "Verificando políticas de segurança"
    
    # Verificar PeerAuthentication
    PEER_AUTH=$(kubectl get peerauthentication -n eagle-services --no-headers 2>/dev/null | wc -l)
    if [ "$PEER_AUTH" -gt 0 ]; then
        log_success "Políticas PeerAuthentication configuradas ($PEER_AUTH encontradas)"
    else
        log_error "Nenhuma política PeerAuthentication encontrada"
    fi
    
    # Verificar AuthorizationPolicy
    AUTH_POLICY=$(kubectl get authorizationpolicy -n eagle-services --no-headers 2>/dev/null | wc -l)
    if [ "$AUTH_POLICY" -gt 0 ]; then
        log_success "Políticas AuthorizationPolicy configuradas ($AUTH_POLICY encontradas)"
    else
        log_error "Nenhuma política AuthorizationPolicy encontrada"
    fi
}

# Verificar configurações de tráfego
test_traffic_management() {
    test_start "Verificando configurações de traffic management"
    
    # Verificar VirtualServices
    VIRTUAL_SERVICES=$(kubectl get virtualservice -n eagle-services --no-headers 2>/dev/null | wc -l)
    if [ "$VIRTUAL_SERVICES" -gt 0 ]; then
        log_success "VirtualServices configurados ($VIRTUAL_SERVICES encontrados)"
    else
        log_error "Nenhum VirtualService encontrado"
    fi
    
    # Verificar DestinationRules
    DEST_RULES=$(kubectl get destinationrule -n eagle-services --no-headers 2>/dev/null | wc -l)
    if [ "$DEST_RULES" -gt 0 ]; then
        log_success "DestinationRules configuradas ($DEST_RULES encontradas)"
    else
        log_error "Nenhuma DestinationRule encontrada"
    fi
    
    # Verificar Gateways
    GATEWAYS=$(kubectl get gateway -n eagle-services --no-headers 2>/dev/null | wc -l)
    if [ "$GATEWAYS" -gt 0 ]; then
        log_success "Gateways configurados ($GATEWAYS encontrados)"
    else
        log_error "Nenhum Gateway encontrado"
    fi
}

# Verificar mTLS
test_mtls_configuration() {
    test_start "Verificando configuração mTLS"
    
    # Verificar se istioctl está disponível
    if command -v istioctl &> /dev/null; then
        # Obter um pod para testar
        POD=$(kubectl get pods -n eagle-services -l app=ms-orchestrator --no-headers 2>/dev/null | head -1 | awk '{print $1}')
        
        if [ -n "$POD" ]; then
            # Verificar status mTLS
            MTLS_STATUS=$(istioctl authn tls-check "$POD.eagle-services" 2>/dev/null | grep -c "OK" || echo "0")
            
            if [ "$MTLS_STATUS" -gt 0 ]; then
                log_success "mTLS configurado e funcionando"
            else
                log_error "mTLS não está funcionando corretamente"
            fi
        else
            log_warning "Nenhum pod encontrado para testar mTLS"
        fi
    else
        log_warning "istioctl não encontrado, pulando teste de mTLS"
    fi
}

# Verificar conectividade entre serviços
test_service_connectivity() {
    test_start "Verificando conectividade entre serviços"
    
    # Obter pod do MS-Orchestrator para testar
    ORCHESTRATOR_POD=$(kubectl get pods -n eagle-services -l app=ms-orchestrator --no-headers 2>/dev/null | head -1 | awk '{print $1}')
    
    if [ -n "$ORCHESTRATOR_POD" ]; then
        # Testar conectividade com MS-Alert
        if kubectl exec -n eagle-services "$ORCHESTRATOR_POD" -c ms-orchestrator -- curl -f -s http://ms-alert:8083/actuator/health > /dev/null 2>&1; then
            log_success "Conectividade MS-Orchestrator -> MS-Alert OK"
        else
            log_error "Falha na conectividade MS-Orchestrator -> MS-Alert"
        fi
        
        # Testar conectividade com MS-Customer
        if kubectl exec -n eagle-services "$ORCHESTRATOR_POD" -c ms-orchestrator -- curl -f -s http://ms-customer:8085/actuator/health > /dev/null 2>&1; then
            log_success "Conectividade MS-Orchestrator -> MS-Customer OK"
        else
            log_error "Falha na conectividade MS-Orchestrator -> MS-Customer"
        fi
    else
        log_warning "Pod MS-Orchestrator não encontrado para teste de conectividade"
    fi
}

# Verificar observabilidade
test_observability() {
    test_start "Verificando configurações de observabilidade"
    
    # Verificar Telemetry
    TELEMETRY=$(kubectl get telemetry -n eagle-services --no-headers 2>/dev/null | wc -l)
    if [ "$TELEMETRY" -gt 0 ]; then
        log_success "Configurações Telemetry encontradas ($TELEMETRY)"
    else
        log_warning "Nenhuma configuração Telemetry encontrada"
    fi
    
    # Verificar se Prometheus está coletando métricas
    if kubectl get pods -n istio-system -l app=prometheus --field-selector=status.phase=Running | grep -q prometheus; then
        log_success "Prometheus está rodando"
    else
        log_warning "Prometheus não está rodando"
    fi
    
    # Verificar se Jaeger está coletando traces
    if kubectl get pods -n istio-system -l app=jaeger --field-selector=status.phase=Running | grep -q jaeger; then
        log_success "Jaeger está rodando"
    else
        log_warning "Jaeger não está rodando"
    fi
}

# Verificar performance e recursos
test_performance() {
    test_start "Verificando performance e recursos"
    
    # Verificar uso de CPU e memória dos sidecars
    SIDECAR_MEMORY=$(kubectl top pods -n eagle-services --containers 2>/dev/null | grep istio-proxy | awk '{sum+=$4} END {print sum}' || echo "0")
    
    if [ "$SIDECAR_MEMORY" != "0" ]; then
        log_success "Sidecars consumindo memória total: ${SIDECAR_MEMORY}Mi"
    else
        log_warning "Não foi possível obter métricas de recursos dos sidecars"
    fi
    
    # Verificar se há pods com restart excessivo
    HIGH_RESTART_PODS=$(kubectl get pods -n eagle-services --no-headers | awk '$4 > 5 {print $1}' | wc -l)
    
    if [ "$HIGH_RESTART_PODS" -eq 0 ]; then
        log_success "Nenhum pod com restarts excessivos"
    else
        log_warning "$HIGH_RESTART_PODS pods com mais de 5 restarts"
    fi
}

# Testar ingress gateway
test_ingress_gateway() {
    test_start "Verificando Ingress Gateway"
    
    # Verificar se Ingress Gateway está rodando
    if kubectl get pods -n istio-system -l app=istio-ingressgateway --field-selector=status.phase=Running | grep -q ingressgateway; then
        log_success "Istio Ingress Gateway está rodando"
        
        # Obter IP/Port do gateway
        INGRESS_HOST=$(kubectl get service istio-ingressgateway -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
        if [ -z "$INGRESS_HOST" ]; then
            INGRESS_HOST=$(kubectl get service istio-ingressgateway -n istio-system -o jsonpath='{.spec.clusterIP}')
        fi
        
        INGRESS_PORT=$(kubectl get service istio-ingressgateway -n istio-system -o jsonpath='{.spec.ports[?(@.name=="http2")].port}')
        
        # Testar acesso através do gateway
        if curl -f -s --max-time 10 "http://$INGRESS_HOST:$INGRESS_PORT/health" > /dev/null 2>&1; then
            log_success "Gateway respondendo em http://$INGRESS_HOST:$INGRESS_PORT"
        else
            log_warning "Gateway não está respondendo ou rota não configurada"
        fi
    else
        log_error "Istio Ingress Gateway não está rodando"
    fi
}

# Executar análise do Istio
test_istio_analyze() {
    test_start "Executando análise do Istio"
    
    if command -v istioctl &> /dev/null; then
        ANALYSIS_OUTPUT=$(istioctl analyze -n eagle-services 2>&1)
        
        if echo "$ANALYSIS_OUTPUT" | grep -q "No validation issues found"; then
            log_success "Análise do Istio: Nenhum problema encontrado"
        else
            log_warning "Análise do Istio encontrou problemas:"
            echo "$ANALYSIS_OUTPUT"
        fi
    else
        log_warning "istioctl não encontrado, pulando análise"
    fi
}

# Mostrar resumo dos testes
show_test_summary() {
    echo ""
    echo "================================================================"
    echo "📊 RESUMO DOS TESTES"
    echo "================================================================"
    echo "Total de testes: $TOTAL_TESTS"
    echo -e "Testes passaram: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Testes falharam: ${RED}$TESTS_FAILED${NC}"
    
    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}✅ Todos os testes passaram!${NC}"
        echo "O Istio Service Mesh está configurado corretamente."
    else
        echo -e "${YELLOW}⚠️  Alguns testes falharam.${NC}"
        echo "Verifique os erros acima e corrija as configurações."
    fi
    
    echo ""
    echo "================================================================"
}

# Mostrar comandos úteis para debug
show_debug_commands() {
    echo "🔧 COMANDOS ÚTEIS PARA DEBUG:"
    echo ""
    echo "Verificar configuração do Istio:"
    echo "  istioctl analyze -n eagle-services"
    echo ""
    echo "Verificar configuração de proxy:"
    echo "  istioctl proxy-config cluster <pod-name> -n eagle-services"
    echo ""
    echo "Verificar certificados mTLS:"
    echo "  istioctl proxy-config secret <pod-name> -n eagle-services"
    echo ""
    echo "Verificar logs do sidecar:"
    echo "  kubectl logs <pod-name> -c istio-proxy -n eagle-services"
    echo ""
    echo "Verificar status do mTLS:"
    echo "  istioctl authn tls-check <pod-name>.eagle-services"
    echo ""
    echo "Verificar métricas do Envoy:"
    echo "  kubectl exec <pod-name> -c istio-proxy -n eagle-services -- curl localhost:15000/stats"
}

# Função principal
main() {
    echo "🔍 Iniciando validação da configuração do Istio..."
    echo "================================================================"
    
    test_istio_installation
    test_namespace_configuration
    test_sidecar_injection
    test_security_policies
    test_traffic_management
    test_mtls_configuration
    test_service_connectivity
    test_observability
    test_performance
    test_ingress_gateway
    test_istio_analyze
    
    show_test_summary
    show_debug_commands
}

# Executar função principal
main "$@"