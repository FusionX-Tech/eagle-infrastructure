package com.eagle.security.tests;

import com.fasterxml.jackson.databind.ObjectMapper;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.SignatureAlgorithm;
import io.jsonwebtoken.security.Keys;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.TestInstance;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureWebMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.security.test.context.support.WithMockUser;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.context.WebApplicationContext;

import javax.crypto.SecretKey;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.Date;
import java.util.HashMap;
import java.util.Map;

import static org.springframework.security.test.web.servlet.setup.SecurityMockMvcConfigurers.springSecurity;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

/**
 * Suite de testes de segurança para os microserviços Eagle
 * 
 * Testa:
 * - Autenticação JWT
 * - Autorização baseada em roles
 * - Validação de tokens
 * - Proteção contra ataques comuns
 * - Headers de segurança
 */
@SpringBootTest
@AutoConfigureWebMvc
@ActiveProfiles("test")
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
public class SecurityTestSuite {

    @Autowired
    private WebApplicationContext context;

    @Autowired
    private ObjectMapper objectMapper;

    private MockMvc mockMvc;
    private SecretKey jwtSecret;
    private String validToken;
    private String expiredToken;
    private String invalidToken;
    private String malformedToken;

    @BeforeEach
    void setUp() {
        mockMvc = MockMvcBuilders
                .webAppContextSetup(context)
                .apply(springSecurity())
                .build();

        // Configurar chave JWT para testes
        jwtSecret = Keys.secretKeyFor(SignatureAlgorithm.HS256);
        
        // Gerar tokens para testes
        generateTestTokens();
    }

    private void generateTestTokens() {
        Instant now = Instant.now();
        
        // Token válido
        validToken = Jwts.builder()
                .setSubject("test-user")
                .setIssuer("http://localhost:8081/realms/eagle-dev")
                .setAudience("eagle-services")
                .setIssuedAt(Date.from(now))
                .setExpiration(Date.from(now.plus(1, ChronoUnit.HOURS)))
                .claim("realm_access", Map.of("roles", new String[]{"MICROSERVICE", "ALERT_CREATE"}))
                .claim("resource_access", Map.of("eagle-services", Map.of("roles", new String[]{"USER"})))
                .claim("preferred_username", "test-user")
                .claim("email", "test@eagle.com")
                .signWith(jwtSecret)
                .compact();

        // Token expirado
        expiredToken = Jwts.builder()
                .setSubject("test-user")
                .setIssuer("http://localhost:8081/realms/eagle-dev")
                .setAudience("eagle-services")
                .setIssuedAt(Date.from(now.minus(2, ChronoUnit.HOURS)))
                .setExpiration(Date.from(now.minus(1, ChronoUnit.HOURS)))
                .claim("realm_access", Map.of("roles", new String[]{"MICROSERVICE"}))
                .signWith(jwtSecret)
                .compact();

        // Token inválido (assinatura incorreta)
        SecretKey wrongKey = Keys.secretKeyFor(SignatureAlgorithm.HS256);
        invalidToken = Jwts.builder()
                .setSubject("test-user")
                .setIssuer("http://localhost:8081/realms/eagle-dev")
                .setExpiration(Date.from(now.plus(1, ChronoUnit.HOURS)))
                .signWith(wrongKey)
                .compact();

        // Token malformado
        malformedToken = "invalid.jwt.token";
    }

    // ========== TESTES DE AUTENTICAÇÃO JWT ==========

    @Test
    @DisplayName("Deve permitir acesso com token JWT válido")
    void shouldAllowAccessWithValidJwtToken() throws Exception {
        mockMvc.perform(get("/api/v1/alerts/status")
                .header(HttpHeaders.AUTHORIZATION, "Bearer " + validToken))
                .andExpect(status().isOk());
    }

    @Test
    @DisplayName("Deve rejeitar requisição sem token JWT")
    void shouldRejectRequestWithoutJwtToken() throws Exception {
        mockMvc.perform(get("/api/v1/alerts/status"))
                .andExpect(status().isUnauthorized());
    }

    @Test
    @DisplayName("Deve rejeitar token JWT expirado")
    void shouldRejectExpiredJwtToken() throws Exception {
        mockMvc.perform(get("/api/v1/alerts/status")
                .header(HttpHeaders.AUTHORIZATION, "Bearer " + expiredToken))
                .andExpect(status().isUnauthorized());
    }

    @Test
    @DisplayName("Deve rejeitar token JWT com assinatura inválida")
    void shouldRejectInvalidJwtSignature() throws Exception {
        mockMvc.perform(get("/api/v1/alerts/status")
                .header(HttpHeaders.AUTHORIZATION, "Bearer " + invalidToken))
                .andExpect(status().isUnauthorized());
    }

    @Test
    @DisplayName("Deve rejeitar token JWT malformado")
    void shouldRejectMalformedJwtToken() throws Exception {
        mockMvc.perform(get("/api/v1/alerts/status")
                .header(HttpHeaders.AUTHORIZATION, "Bearer " + malformedToken))
                .andExpect(status().isUnauthorized());
    }

    @Test
    @DisplayName("Deve rejeitar header Authorization inválido")
    void shouldRejectInvalidAuthorizationHeader() throws Exception {
        mockMvc.perform(get("/api/v1/alerts/status")
                .header(HttpHeaders.AUTHORIZATION, "InvalidFormat " + validToken))
                .andExpect(status().isUnauthorized());
    }

    // ========== TESTES DE AUTORIZAÇÃO ==========

    @Test
    @DisplayName("Deve permitir acesso com role adequada")
    @WithMockUser(roles = {"ALERT_CREATE", "MICROSERVICE"})
    void shouldAllowAccessWithProperRole() throws Exception {
        Map<String, Object> alertRequest = new HashMap<>();
        alertRequest.put("customerDocument", "12345678901");
        alertRequest.put("scopeStartDate", "2024-01-01");
        alertRequest.put("scopeEndDate", "2024-01-31");

        mockMvc.perform(post("/api/v1/alerts/create")
                .header(HttpHeaders.AUTHORIZATION, "Bearer " + validToken)
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(alertRequest)))
                .andExpect(status().isOk());
    }

    @Test
    @DisplayName("Deve rejeitar acesso sem role adequada")
    void shouldRejectAccessWithoutProperRole() throws Exception {
        // Token sem role ALERT_CREATE
        String tokenWithoutRole = Jwts.builder()
                .setSubject("test-user")
                .setIssuer("http://localhost:8081/realms/eagle-dev")
                .setExpiration(Date.from(Instant.now().plus(1, ChronoUnit.HOURS)))
                .claim("realm_access", Map.of("roles", new String[]{"USER"}))
                .signWith(jwtSecret)
                .compact();

        Map<String, Object> alertRequest = new HashMap<>();
        alertRequest.put("customerDocument", "12345678901");
        alertRequest.put("scopeStartDate", "2024-01-01");
        alertRequest.put("scopeEndDate", "2024-01-31");

        mockMvc.perform(post("/api/v1/alerts/create")
                .header(HttpHeaders.AUTHORIZATION, "Bearer " + tokenWithoutRole)
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(alertRequest)))
                .andExpect(status().isForbidden());
    }

    // ========== TESTES DE VALIDAÇÃO DE ENTRADA ==========

    @Test
    @DisplayName("Deve rejeitar payload com dados inválidos")
    void shouldRejectInvalidPayload() throws Exception {
        Map<String, Object> invalidRequest = new HashMap<>();
        invalidRequest.put("customerDocument", ""); // Documento vazio
        invalidRequest.put("scopeStartDate", "invalid-date");
        invalidRequest.put("scopeEndDate", null);

        mockMvc.perform(post("/api/v1/alerts/create")
                .header(HttpHeaders.AUTHORIZATION, "Bearer " + validToken)
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(invalidRequest)))
                .andExpect(status().isBadRequest());
    }

    @Test
    @DisplayName("Deve rejeitar payload muito grande")
    void shouldRejectOversizedPayload() throws Exception {
        Map<String, Object> oversizedRequest = new HashMap<>();
        oversizedRequest.put("customerDocument", "12345678901");
        oversizedRequest.put("scopeStartDate", "2024-01-01");
        oversizedRequest.put("scopeEndDate", "2024-01-31");
        
        // Adicionar campo muito grande
        StringBuilder largeString = new StringBuilder();
        for (int i = 0; i < 100000; i++) {
            largeString.append("A");
        }
        oversizedRequest.put("largeField", largeString.toString());

        mockMvc.perform(post("/api/v1/alerts/create")
                .header(HttpHeaders.AUTHORIZATION, "Bearer " + validToken)
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(oversizedRequest)))
                .andExpect(status().isPayloadTooLarge());
    }

    // ========== TESTES DE INJEÇÃO ==========

    @Test
    @DisplayName("Deve prevenir SQL Injection")
    void shouldPreventSqlInjection() throws Exception {
        Map<String, Object> sqlInjectionRequest = new HashMap<>();
        sqlInjectionRequest.put("customerDocument", "'; DROP TABLE alerts; --");
        sqlInjectionRequest.put("scopeStartDate", "2024-01-01");
        sqlInjectionRequest.put("scopeEndDate", "2024-01-31");

        mockMvc.perform(post("/api/v1/alerts/create")
                .header(HttpHeaders.AUTHORIZATION, "Bearer " + validToken)
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(sqlInjectionRequest)))
                .andExpect(status().isBadRequest());
    }

    @Test
    @DisplayName("Deve prevenir XSS")
    void shouldPreventXss() throws Exception {
        Map<String, Object> xssRequest = new HashMap<>();
        xssRequest.put("customerDocument", "<script>alert('xss')</script>");
        xssRequest.put("scopeStartDate", "2024-01-01");
        xssRequest.put("scopeEndDate", "2024-01-31");

        mockMvc.perform(post("/api/v1/alerts/create")
                .header(HttpHeaders.AUTHORIZATION, "Bearer " + validToken)
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(xssRequest)))
                .andExpect(status().isBadRequest());
    }

    // ========== TESTES DE HEADERS DE SEGURANÇA ==========

    @Test
    @DisplayName("Deve incluir headers de segurança obrigatórios")
    void shouldIncludeMandatorySecurityHeaders() throws Exception {
        mockMvc.perform(get("/api/v1/alerts/status")
                .header(HttpHeaders.AUTHORIZATION, "Bearer " + validToken))
                .andExpect(status().isOk())
                .andExpect(header().exists("X-Content-Type-Options"))
                .andExpect(header().string("X-Content-Type-Options", "nosniff"))
                .andExpect(header().exists("X-Frame-Options"))
                .andExpect(header().string("X-Frame-Options", "DENY"))
                .andExpect(header().exists("X-XSS-Protection"))
                .andExpect(header().string("X-XSS-Protection", "1; mode=block"))
                .andExpect(header().exists("Strict-Transport-Security"));
    }

    @Test
    @DisplayName("Deve configurar CORS adequadamente")
    void shouldConfigureCorsCorrectly() throws Exception {
        mockMvc.perform(options("/api/v1/alerts/create")
                .header("Origin", "http://localhost:3000")
                .header("Access-Control-Request-Method", "POST")
                .header("Access-Control-Request-Headers", "Authorization,Content-Type"))
                .andExpect(status().isOk())
                .andExpect(header().exists("Access-Control-Allow-Origin"))
                .andExpect(header().exists("Access-Control-Allow-Methods"))
                .andExpect(header().exists("Access-Control-Allow-Headers"));
    }

    // ========== TESTES DE RATE LIMITING ==========

    @Test
    @DisplayName("Deve aplicar rate limiting")
    void shouldApplyRateLimiting() throws Exception {
        // Fazer múltiplas requisições rapidamente
        for (int i = 0; i < 100; i++) {
            mockMvc.perform(get("/api/v1/alerts/status")
                    .header(HttpHeaders.AUTHORIZATION, "Bearer " + validToken));
        }

        // A próxima requisição deve ser rejeitada por rate limiting
        mockMvc.perform(get("/api/v1/alerts/status")
                .header(HttpHeaders.AUTHORIZATION, "Bearer " + validToken))
                .andExpect(status().isTooManyRequests());
    }

    // ========== TESTES DE ENDPOINTS SENSÍVEIS ==========

    @Test
    @DisplayName("Deve proteger endpoints de actuator")
    void shouldProtectActuatorEndpoints() throws Exception {
        // Endpoints sensíveis devem exigir autenticação
        mockMvc.perform(get("/actuator/env"))
                .andExpect(status().isUnauthorized());

        mockMvc.perform(get("/actuator/configprops"))
                .andExpect(status().isUnauthorized());

        mockMvc.perform(get("/actuator/beans"))
                .andExpect(status().isUnauthorized());
    }

    @Test
    @DisplayName("Deve permitir acesso a endpoints públicos de actuator")
    void shouldAllowAccessToPublicActuatorEndpoints() throws Exception {
        // Health e info devem ser públicos
        mockMvc.perform(get("/actuator/health"))
                .andExpect(status().isOk());

        mockMvc.perform(get("/actuator/info"))
                .andExpect(status().isOk());
    }

    // ========== TESTES DE TIMEOUT E CIRCUIT BREAKER ==========

    @Test
    @DisplayName("Deve aplicar timeout em requisições longas")
    void shouldApplyTimeoutToLongRequests() throws Exception {
        // Simular requisição que demora muito
        mockMvc.perform(get("/api/v1/alerts/slow-endpoint")
                .header(HttpHeaders.AUTHORIZATION, "Bearer " + validToken))
                .andExpect(status().isRequestTimeout());
    }

    // ========== TESTES DE AUDITORIA ==========

    @Test
    @DisplayName("Deve registrar tentativas de acesso não autorizado")
    void shouldLogUnauthorizedAccessAttempts() throws Exception {
        // Fazer requisição não autorizada
        mockMvc.perform(post("/api/v1/alerts/create")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"customerDocument\":\"12345678901\"}"));

        // Verificar se foi logado (implementar verificação de logs)
        // Esta verificação dependeria da implementação específica de logging
    }

    @Test
    @DisplayName("Deve registrar operações sensíveis")
    void shouldLogSensitiveOperations() throws Exception {
        Map<String, Object> alertRequest = new HashMap<>();
        alertRequest.put("customerDocument", "12345678901");
        alertRequest.put("scopeStartDate", "2024-01-01");
        alertRequest.put("scopeEndDate", "2024-01-31");

        mockMvc.perform(post("/api/v1/alerts/create")
                .header(HttpHeaders.AUTHORIZATION, "Bearer " + validToken)
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(alertRequest)));

        // Verificar se a operação foi logada para auditoria
        // Esta verificação dependeria da implementação específica de auditoria
    }

    // ========== TESTES DE CRIPTOGRAFIA ==========

    @Test
    @DisplayName("Deve usar HTTPS em produção")
    void shouldUseHttpsInProduction() throws Exception {
        // Verificar se requisições HTTP são redirecionadas para HTTPS
        // Este teste seria mais relevante em ambiente de produção
        mockMvc.perform(get("/api/v1/alerts/status")
                .header(HttpHeaders.AUTHORIZATION, "Bearer " + validToken)
                .secure(false))
                .andExpect(status().isMovedPermanently());
    }

    // ========== TESTES DE DADOS SENSÍVEIS ==========

    @Test
    @DisplayName("Não deve expor dados sensíveis em respostas de erro")
    void shouldNotExposeSensitiveDataInErrorResponses() throws Exception {
        mockMvc.perform(get("/api/v1/alerts/nonexistent")
                .header(HttpHeaders.AUTHORIZATION, "Bearer " + validToken))
                .andExpect(status().isNotFound())
                .andExpect(content().string(org.hamcrest.Matchers.not(
                    org.hamcrest.Matchers.containsString("password"))))
                .andExpect(content().string(org.hamcrest.Matchers.not(
                    org.hamcrest.Matchers.containsString("secret"))))
                .andExpect(content().string(org.hamcrest.Matchers.not(
                    org.hamcrest.Matchers.containsString("token"))));
    }
}