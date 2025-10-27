#!/usr/bin/env python3
"""
Testes de Penetração Automatizados para o Sistema Eagle

Este script executa testes de segurança automatizados incluindo:
- Testes de autenticação e autorização
- Testes de injeção (SQL, XSS, Command)
- Testes de configuração de segurança
- Testes de exposição de dados sensíveis
- Testes de rate limiting
- Testes de headers de segurança

Uso:
    python penetration-tests.py --target http://localhost:8080 --token <jwt-token>
"""

import argparse
import requests
import json
import time
import sys
from urllib.parse import urljoin
from typing import Dict, List, Tuple
import jwt
from datetime import datetime, timedelta
import base64
import hashlib

class EaglePenetrationTester:
    def __init__(self, base_url: str, auth_token: str = None):
        self.base_url = base_url.rstrip('/')
        self.auth_token = auth_token
        self.session = requests.Session()
        self.results = []
        
        # Headers padrão
        self.session.headers.update({
            'User-Agent': 'Eagle-Security-Tester/1.0',
            'Content-Type': 'application/json'
        })
        
        if auth_token:
            self.session.headers.update({
                'Authorization': f'Bearer {auth_token}'
            })

    def log_result(self, test_name: str, status: str, details: str, severity: str = "INFO"):
        """Registra resultado de um teste"""
        result = {
            'timestamp': datetime.now().isoformat(),
            'test': test_name,
            'status': status,
            'details': details,
            'severity': severity
        }
        self.results.append(result)
        
        # Cores para output
        colors = {
            'PASS': '\033[92m',  # Verde
            'FAIL': '\033[91m',  # Vermelho
            'WARN': '\033[93m',  # Amarelo
            'INFO': '\033[94m',  # Azul
            'END': '\033[0m'     # Reset
        }
        
        color = colors.get(severity, colors['INFO'])
        print(f"{color}[{severity}] {test_name}: {status}{colors['END']}")
        if details:
            print(f"    {details}")

    def test_authentication(self):
        """Testa vulnerabilidades de autenticação"""
        print("\n=== TESTES DE AUTENTICAÇÃO ===")
        
        # Teste 1: Acesso sem token
        try:
            response = requests.get(f"{self.base_url}/api/v1/alerts/status")
            if response.status_code == 401:
                self.log_result("Auth Without Token", "PASS", 
                              "Endpoint protegido corretamente", "PASS")
            else:
                self.log_result("Auth Without Token", "FAIL", 
                              f"Endpoint não protegido (status: {response.status_code})", "FAIL")
        except Exception as e:
            self.log_result("Auth Without Token", "ERROR", str(e), "WARN")

        # Teste 2: Token malformado
        malformed_tokens = [
            "invalid.jwt.token",
            "Bearer invalid",
            "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.invalid",
            ""
        ]
        
        for token in malformed_tokens:
            try:
                headers = {'Authorization': f'Bearer {token}'}
                response = requests.get(f"{self.base_url}/api/v1/alerts/status", headers=headers)
                if response.status_code == 401:
                    self.log_result(f"Malformed Token ({token[:20]}...)", "PASS", 
                                  "Token inválido rejeitado", "PASS")
                else:
                    self.log_result(f"Malformed Token ({token[:20]}...)", "FAIL", 
                                  f"Token inválido aceito (status: {response.status_code})", "FAIL")
            except Exception as e:
                self.log_result(f"Malformed Token", "ERROR", str(e), "WARN")

        # Teste 3: Token expirado (se possível gerar)
        try:
            expired_token = self.generate_expired_token()
            if expired_token:
                headers = {'Authorization': f'Bearer {expired_token}'}
                response = requests.get(f"{self.base_url}/api/v1/alerts/status", headers=headers)
                if response.status_code == 401:
                    self.log_result("Expired Token", "PASS", 
                                  "Token expirado rejeitado", "PASS")
                else:
                    self.log_result("Expired Token", "FAIL", 
                                  f"Token expirado aceito (status: {response.status_code})", "FAIL")
        except Exception as e:
            self.log_result("Expired Token", "WARN", f"Não foi possível testar: {e}", "WARN")

    def test_authorization(self):
        """Testa vulnerabilidades de autorização"""
        print("\n=== TESTES DE AUTORIZAÇÃO ===")
        
        # Teste de escalação de privilégios
        sensitive_endpoints = [
            "/actuator/env",
            "/actuator/configprops", 
            "/actuator/beans",
            "/actuator/heapdump",
            "/actuator/threaddump",
            "/admin/users",
            "/admin/config"
        ]
        
        for endpoint in sensitive_endpoints:
            try:
                response = self.session.get(f"{self.base_url}{endpoint}")
                if response.status_code in [401, 403, 404]:
                    self.log_result(f"Sensitive Endpoint {endpoint}", "PASS", 
                                  f"Endpoint protegido (status: {response.status_code})", "PASS")
                else:
                    self.log_result(f"Sensitive Endpoint {endpoint}", "FAIL", 
                                  f"Endpoint exposto (status: {response.status_code})", "FAIL")
            except Exception as e:
                self.log_result(f"Sensitive Endpoint {endpoint}", "ERROR", str(e), "WARN")

    def test_injection_attacks(self):
        """Testa vulnerabilidades de injeção"""
        print("\n=== TESTES DE INJEÇÃO ===")
        
        # Payloads de SQL Injection
        sql_payloads = [
            "'; DROP TABLE alerts; --",
            "' OR '1'='1",
            "' UNION SELECT * FROM users --",
            "'; INSERT INTO alerts VALUES ('malicious'); --",
            "' OR 1=1 --"
        ]
        
        # Payloads de XSS
        xss_payloads = [
            "<script>alert('xss')</script>",
            "javascript:alert('xss')",
            "<img src=x onerror=alert('xss')>",
            "';alert('xss');//",
            "<svg onload=alert('xss')>"
        ]
        
        # Payloads de Command Injection
        cmd_payloads = [
            "; ls -la",
            "| whoami",
            "&& cat /etc/passwd",
            "`id`",
            "$(whoami)"
        ]
        
        # Testar SQL Injection
        for payload in sql_payloads:
            self.test_injection_payload("SQL Injection", payload, "customerDocument")
        
        # Testar XSS
        for payload in xss_payloads:
            self.test_injection_payload("XSS", payload, "customerDocument")
        
        # Testar Command Injection
        for payload in cmd_payloads:
            self.test_injection_payload("Command Injection", payload, "customerDocument")

    def test_injection_payload(self, attack_type: str, payload: str, field: str):
        """Testa um payload específico de injeção"""
        try:
            data = {
                field: payload,
                "scopeStartDate": "2024-01-01",
                "scopeEndDate": "2024-01-31"
            }
            
            response = self.session.post(f"{self.base_url}/api/v1/alerts/create", 
                                       json=data)
            
            # Verificar se o payload foi rejeitado
            if response.status_code in [400, 422]:
                self.log_result(f"{attack_type} ({payload[:30]}...)", "PASS", 
                              "Payload rejeitado", "PASS")
            elif response.status_code == 200:
                # Verificar se há sinais de execução bem-sucedida
                response_text = response.text.lower()
                if any(keyword in response_text for keyword in ['error', 'exception', 'stack']):
                    self.log_result(f"{attack_type} ({payload[:30]}...)", "WARN", 
                                  "Possível vulnerabilidade detectada", "WARN")
                else:
                    self.log_result(f"{attack_type} ({payload[:30]}...)", "FAIL", 
                                  "Payload aceito sem validação", "FAIL")
            else:
                self.log_result(f"{attack_type} ({payload[:30]}...)", "INFO", 
                              f"Status inesperado: {response.status_code}", "INFO")
                
        except Exception as e:
            self.log_result(f"{attack_type} Payload Test", "ERROR", str(e), "WARN")

    def test_security_headers(self):
        """Testa headers de segurança"""
        print("\n=== TESTES DE HEADERS DE SEGURANÇA ===")
        
        required_headers = {
            'X-Content-Type-Options': 'nosniff',
            'X-Frame-Options': ['DENY', 'SAMEORIGIN'],
            'X-XSS-Protection': '1; mode=block',
            'Strict-Transport-Security': None,  # Qualquer valor é aceitável
            'Content-Security-Policy': None
        }
        
        try:
            response = self.session.get(f"{self.base_url}/api/v1/alerts/status")
            
            for header, expected_value in required_headers.items():
                if header in response.headers:
                    actual_value = response.headers[header]
                    if expected_value is None:
                        self.log_result(f"Security Header {header}", "PASS", 
                                      f"Presente: {actual_value}", "PASS")
                    elif isinstance(expected_value, list):
                        if actual_value in expected_value:
                            self.log_result(f"Security Header {header}", "PASS", 
                                          f"Valor correto: {actual_value}", "PASS")
                        else:
                            self.log_result(f"Security Header {header}", "WARN", 
                                          f"Valor inesperado: {actual_value}", "WARN")
                    elif actual_value == expected_value:
                        self.log_result(f"Security Header {header}", "PASS", 
                                      f"Valor correto: {actual_value}", "PASS")
                    else:
                        self.log_result(f"Security Header {header}", "WARN", 
                                      f"Valor incorreto: {actual_value}", "WARN")
                else:
                    self.log_result(f"Security Header {header}", "FAIL", 
                                  "Header ausente", "FAIL")
                    
        except Exception as e:
            self.log_result("Security Headers Test", "ERROR", str(e), "WARN")

    def test_rate_limiting(self):
        """Testa rate limiting"""
        print("\n=== TESTES DE RATE LIMITING ===")
        
        try:
            # Fazer múltiplas requisições rapidamente
            responses = []
            for i in range(50):
                response = self.session.get(f"{self.base_url}/api/v1/alerts/status")
                responses.append(response.status_code)
                time.sleep(0.1)  # Pequeno delay
            
            # Verificar se alguma requisição foi limitada
            rate_limited = any(status == 429 for status in responses)
            
            if rate_limited:
                self.log_result("Rate Limiting", "PASS", 
                              "Rate limiting ativo", "PASS")
            else:
                self.log_result("Rate Limiting", "WARN", 
                              "Rate limiting não detectado", "WARN")
                
        except Exception as e:
            self.log_result("Rate Limiting Test", "ERROR", str(e), "WARN")

    def test_information_disclosure(self):
        """Testa vazamento de informações"""
        print("\n=== TESTES DE VAZAMENTO DE INFORMAÇÕES ===")
        
        # Endpoints que podem vazar informações
        info_endpoints = [
            "/actuator/info",
            "/actuator/health",
            "/actuator/metrics",
            "/swagger-ui.html",
            "/api-docs",
            "/error",
            "/debug"
        ]
        
        sensitive_keywords = [
            'password', 'secret', 'key', 'token', 'credential',
            'database', 'connection', 'jdbc', 'username',
            'stacktrace', 'exception', 'error'
        ]
        
        for endpoint in info_endpoints:
            try:
                response = requests.get(f"{self.base_url}{endpoint}")
                
                if response.status_code == 200:
                    content = response.text.lower()
                    found_sensitive = [kw for kw in sensitive_keywords if kw in content]
                    
                    if found_sensitive:
                        self.log_result(f"Info Disclosure {endpoint}", "WARN", 
                                      f"Possível vazamento: {', '.join(found_sensitive)}", "WARN")
                    else:
                        self.log_result(f"Info Disclosure {endpoint}", "PASS", 
                                      "Nenhuma informação sensível detectada", "PASS")
                else:
                    self.log_result(f"Info Disclosure {endpoint}", "PASS", 
                                  f"Endpoint não acessível (status: {response.status_code})", "PASS")
                    
            except Exception as e:
                self.log_result(f"Info Disclosure {endpoint}", "ERROR", str(e), "WARN")

    def test_cors_configuration(self):
        """Testa configuração CORS"""
        print("\n=== TESTES DE CONFIGURAÇÃO CORS ===")
        
        try:
            # Testar CORS com origem maliciosa
            malicious_origins = [
                "http://evil.com",
                "https://attacker.com",
                "null",
                "*"
            ]
            
            for origin in malicious_origins:
                headers = {
                    'Origin': origin,
                    'Access-Control-Request-Method': 'POST',
                    'Access-Control-Request-Headers': 'Authorization,Content-Type'
                }
                
                response = requests.options(f"{self.base_url}/api/v1/alerts/create", 
                                          headers=headers)
                
                cors_origin = response.headers.get('Access-Control-Allow-Origin')
                
                if cors_origin == origin or cors_origin == '*':
                    self.log_result(f"CORS Origin {origin}", "FAIL", 
                                  f"Origem maliciosa permitida: {cors_origin}", "FAIL")
                else:
                    self.log_result(f"CORS Origin {origin}", "PASS", 
                                  "Origem maliciosa rejeitada", "PASS")
                    
        except Exception as e:
            self.log_result("CORS Configuration Test", "ERROR", str(e), "WARN")

    def test_ssl_configuration(self):
        """Testa configuração SSL/TLS"""
        print("\n=== TESTES DE CONFIGURAÇÃO SSL/TLS ===")
        
        if not self.base_url.startswith('https://'):
            self.log_result("SSL Configuration", "WARN", 
                          "Aplicação não está usando HTTPS", "WARN")
            return
        
        try:
            # Testar redirecionamento HTTP para HTTPS
            http_url = self.base_url.replace('https://', 'http://')
            response = requests.get(http_url, allow_redirects=False)
            
            if response.status_code in [301, 302, 307, 308]:
                location = response.headers.get('Location', '')
                if location.startswith('https://'):
                    self.log_result("HTTP to HTTPS Redirect", "PASS", 
                                  "Redirecionamento configurado", "PASS")
                else:
                    self.log_result("HTTP to HTTPS Redirect", "FAIL", 
                                  "Redirecionamento incorreto", "FAIL")
            else:
                self.log_result("HTTP to HTTPS Redirect", "FAIL", 
                              "Redirecionamento não configurado", "FAIL")
                
        except Exception as e:
            self.log_result("SSL Configuration Test", "ERROR", str(e), "WARN")

    def generate_expired_token(self):
        """Gera um token JWT expirado para testes"""
        try:
            # Token simples expirado (sem validação de assinatura)
            header = {"alg": "HS256", "typ": "JWT"}
            payload = {
                "sub": "test-user",
                "iss": "http://localhost:8081/realms/eagle-dev",
                "exp": int((datetime.now() - timedelta(hours=1)).timestamp()),
                "iat": int((datetime.now() - timedelta(hours=2)).timestamp())
            }
            
            # Codificar sem assinatura válida (apenas para teste)
            header_b64 = base64.urlsafe_b64encode(json.dumps(header).encode()).decode().rstrip('=')
            payload_b64 = base64.urlsafe_b64encode(json.dumps(payload).encode()).decode().rstrip('=')
            signature = "fake_signature"
            
            return f"{header_b64}.{payload_b64}.{signature}"
            
        except Exception:
            return None

    def generate_report(self):
        """Gera relatório final dos testes"""
        print("\n" + "="*60)
        print("RELATÓRIO FINAL DE TESTES DE SEGURANÇA")
        print("="*60)
        
        total_tests = len(self.results)
        passed = len([r for r in self.results if r['status'] == 'PASS'])
        failed = len([r for r in self.results if r['status'] == 'FAIL'])
        warnings = len([r for r in self.results if r['status'] == 'WARN'])
        errors = len([r for r in self.results if r['status'] == 'ERROR'])
        
        print(f"Total de testes: {total_tests}")
        print(f"Passou: {passed}")
        print(f"Falhou: {failed}")
        print(f"Avisos: {warnings}")
        print(f"Erros: {errors}")
        
        if failed > 0:
            print(f"\n⚠️  VULNERABILIDADES CRÍTICAS ENCONTRADAS: {failed}")
            for result in self.results:
                if result['status'] == 'FAIL':
                    print(f"  - {result['test']}: {result['details']}")
        
        if warnings > 0:
            print(f"\n⚠️  POSSÍVEIS PROBLEMAS DE SEGURANÇA: {warnings}")
            for result in self.results:
                if result['status'] == 'WARN':
                    print(f"  - {result['test']}: {result['details']}")
        
        # Salvar relatório em arquivo
        report_file = f"security_report_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
        with open(report_file, 'w') as f:
            json.dump(self.results, f, indent=2)
        
        print(f"\nRelatório detalhado salvo em: {report_file}")
        
        return failed == 0  # Retorna True se não há falhas críticas

    def run_all_tests(self):
        """Executa todos os testes de segurança"""
        print("Iniciando testes de penetração automatizados...")
        print(f"Target: {self.base_url}")
        
        self.test_authentication()
        self.test_authorization()
        self.test_injection_attacks()
        self.test_security_headers()
        self.test_rate_limiting()
        self.test_information_disclosure()
        self.test_cors_configuration()
        self.test_ssl_configuration()
        
        return self.generate_report()

def main():
    parser = argparse.ArgumentParser(description='Eagle Security Penetration Testing Tool')
    parser.add_argument('--target', required=True, help='Target URL (e.g., http://localhost:8080)')
    parser.add_argument('--token', help='JWT token for authenticated tests')
    parser.add_argument('--output', help='Output file for detailed report')
    
    args = parser.parse_args()
    
    tester = EaglePenetrationTester(args.target, args.token)
    success = tester.run_all_tests()
    
    # Exit code baseado no resultado
    sys.exit(0 if success else 1)

if __name__ == "__main__":
    main()