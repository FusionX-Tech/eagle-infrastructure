package com.eagle.config;

import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.Timer;
import io.micrometer.core.instrument.binder.MeterBinder;
import io.micrometer.observation.ObservationRegistry;
import io.micrometer.tracing.Tracer;
import io.micrometer.tracing.annotation.NewSpan;
import io.micrometer.tracing.annotation.SpanTag;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.actuate.autoconfigure.observation.ObservationAutoConfiguration;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Import;
import org.springframework.web.filter.CommonsRequestLoggingFilter;

import jakarta.servlet.http.HttpServletRequest;
import java.util.concurrent.atomic.AtomicLong;

/**
 * Configuração de observabilidade para os microserviços Eagle
 * 
 * Esta classe configura:
 * - Métricas customizadas de negócio
 * - Distributed tracing com tags customizadas
 * - Observability registry
 * - Request logging para debugging
 */
@Configuration
@Import(ObservationAutoConfiguration.class)
@ConditionalOnProperty(name = "eagle.observability.enabled", havingValue = "true", matchIfMissing = true)
public class ObservabilityConfig {

    @Value("${spring.application.name}")
    private String applicationName;

    @Value("${eagle.observability.business-metrics.enabled:true}")
    private boolean businessMetricsEnabled;

    /**
     * Configuração de métricas customizadas para alertas
     */
    @Bean
    @ConditionalOnProperty(name = "eagle.observability.business-metrics.alert-creation.enabled", havingValue = "true")
    public AlertMetrics alertMetrics(MeterRegistry meterRegistry) {
        return new AlertMetrics(meterRegistry, applicationName);
    }

    /**
     * Configuração de métricas customizadas para SQS
     */
    @Bean
    @ConditionalOnProperty(name = "eagle.observability.business-metrics.sqs-processing.enabled", havingValue = "true")
    public SqsMetrics sqsMetrics(MeterRegistry meterRegistry) {
        return new SqsMetrics(meterRegistry, applicationName);
    }

    /**
     * Configuração de tracing customizado
     */
    @Bean
    @ConditionalOnProperty(name = "eagle.observability.tracing.enabled", havingValue = "true")
    public TracingService tracingService(Tracer tracer) {
        return new TracingService(tracer);
    }

    /**
     * Request logging filter para debugging
     */
    @Bean
    public CommonsRequestLoggingFilter requestLoggingFilter() {
        CommonsRequestLoggingFilter filter = new CommonsRequestLoggingFilter();
        filter.setIncludeQueryString(true);
        filter.setIncludePayload(false); // Não incluir payload por segurança
        filter.setIncludeHeaders(true);
        filter.setIncludeClientInfo(true);
        filter.setMaxPayloadLength(1000);
        filter.setBeforeMessagePrefix("REQUEST: ");
        filter.setAfterMessagePrefix("RESPONSE: ");
        return filter;
    }

    /**
     * Classe para métricas de alertas
     */
    public static class AlertMetrics implements MeterBinder {
        private final MeterRegistry meterRegistry;
        private final String applicationName;
        
        private Counter alertCreationCounter;
        private Counter alertEnrichmentCounter;
        private Timer alertCreationTimer;
        private Timer alertEnrichmentTimer;
        private AtomicLong activeAlertsGauge;

        public AlertMetrics(MeterRegistry meterRegistry, String applicationName) {
            this.meterRegistry = meterRegistry;
            this.applicationName = applicationName;
            this.activeAlertsGauge = new AtomicLong(0);
        }

        @Override
        public void bindTo(MeterRegistry registry) {
            // Contador de alertas criados
            this.alertCreationCounter = Counter.builder("alert.creation.total")
                    .description("Total number of alerts created")
                    .tag("service", applicationName)
                    .register(registry);

            // Contador de alertas enriquecidos
            this.alertEnrichmentCounter = Counter.builder("alert.enrichment.total")
                    .description("Total number of alerts enriched")
                    .tag("service", applicationName)
                    .register(registry);

            // Timer para criação de alertas
            this.alertCreationTimer = Timer.builder("alert.creation.duration")
                    .description("Time taken to create an alert")
                    .tag("service", applicationName)
                    .register(registry);

            // Timer para enriquecimento de alertas
            this.alertEnrichmentTimer = Timer.builder("alert.enrichment.duration")
                    .description("Time taken to enrich an alert")
                    .tag("service", applicationName)
                    .register(registry);

            // Gauge para alertas ativos
            registry.gauge("alert.active.count", 
                    "Number of active alerts", 
                    activeAlertsGauge);
        }

        public void incrementAlertCreation(String status, String customerType) {
            alertCreationCounter.increment(
                "status", status,
                "customer_type", customerType
            );
        }

        public void incrementAlertEnrichment(String status, String enrichmentType) {
            alertEnrichmentCounter.increment(
                "status", status,
                "enrichment_type", enrichmentType
            );
        }

        public Timer.Sample startAlertCreationTimer() {
            return Timer.start(meterRegistry);
        }

        public Timer.Sample startAlertEnrichmentTimer() {
            return Timer.start(meterRegistry);
        }

        public void recordAlertCreationTime(Timer.Sample sample, String status) {
            sample.stop(alertCreationTimer.tag("status", status));
        }

        public void recordAlertEnrichmentTime(Timer.Sample sample, String status, String type) {
            sample.stop(alertEnrichmentTimer.tag("status", status, "type", type));
        }

        public void setActiveAlertsCount(long count) {
            activeAlertsGauge.set(count);
        }
    }

    /**
     * Classe para métricas de SQS
     */
    public static class SqsMetrics implements MeterBinder {
        private final MeterRegistry meterRegistry;
        private final String applicationName;
        
        private Counter messagesSentCounter;
        private Counter messagesReceivedCounter;
        private Counter messagesFailedCounter;
        private Timer messageProcessingTimer;

        public SqsMetrics(MeterRegistry meterRegistry, String applicationName) {
            this.meterRegistry = meterRegistry;
            this.applicationName = applicationName;
        }

        @Override
        public void bindTo(MeterRegistry registry) {
            // Contador de mensagens enviadas
            this.messagesSentCounter = Counter.builder("sqs.messages.sent.total")
                    .description("Total number of SQS messages sent")
                    .tag("service", applicationName)
                    .register(registry);

            // Contador de mensagens recebidas
            this.messagesReceivedCounter = Counter.builder("sqs.messages.received.total")
                    .description("Total number of SQS messages received")
                    .tag("service", applicationName)
                    .register(registry);

            // Contador de mensagens com falha
            this.messagesFailedCounter = Counter.builder("sqs.messages.failed.total")
                    .description("Total number of SQS messages that failed processing")
                    .tag("service", applicationName)
                    .register(registry);

            // Timer para processamento de mensagens
            this.messageProcessingTimer = Timer.builder("sqs.message.processing.duration")
                    .description("Time taken to process SQS messages")
                    .tag("service", applicationName)
                    .register(registry);
        }

        public void incrementMessagesSent(String queueName, String messageType) {
            messagesSentCounter.increment(
                "queue_name", queueName,
                "message_type", messageType
            );
        }

        public void incrementMessagesReceived(String queueName, String messageType) {
            messagesReceivedCounter.increment(
                "queue_name", queueName,
                "message_type", messageType
            );
        }

        public void incrementMessagesFailed(String queueName, String messageType, String errorType) {
            messagesFailedCounter.increment(
                "queue_name", queueName,
                "message_type", messageType,
                "error_type", errorType
            );
        }

        public Timer.Sample startMessageProcessingTimer() {
            return Timer.start(meterRegistry);
        }

        public void recordMessageProcessingTime(Timer.Sample sample, String queueName, String messageType, String status) {
            sample.stop(messageProcessingTimer.tag(
                "queue_name", queueName,
                "message_type", messageType,
                "status", status
            ));
        }
    }

    /**
     * Serviço para tracing customizado
     */
    public static class TracingService {
        private final Tracer tracer;

        public TracingService(Tracer tracer) {
            this.tracer = tracer;
        }

        @NewSpan("alert-creation")
        public void traceAlertCreation(@SpanTag("customer.document") String customerDocument,
                                     @SpanTag("alert.id") String alertId,
                                     @SpanTag("process.id") String processId) {
            // Adicionar tags customizadas ao span atual
            if (tracer.currentSpan() != null) {
                tracer.currentSpan()
                    .tag("business.domain", "alert-system")
                    .tag("operation.type", "create")
                    .tag("service.name", "ms-alert");
            }
        }

        @NewSpan("alert-enrichment")
        public void traceAlertEnrichment(@SpanTag("alert.id") String alertId,
                                       @SpanTag("enrichment.type") String enrichmentType,
                                       @SpanTag("customer.document") String customerDocument) {
            if (tracer.currentSpan() != null) {
                tracer.currentSpan()
                    .tag("business.domain", "alert-system")
                    .tag("operation.type", "enrich")
                    .tag("service.name", "ms-enrichment");
            }
        }

        @NewSpan("sqs-message-processing")
        public void traceSqsMessageProcessing(@SpanTag("queue.name") String queueName,
                                            @SpanTag("message.type") String messageType,
                                            @SpanTag("message.id") String messageId) {
            if (tracer.currentSpan() != null) {
                tracer.currentSpan()
                    .tag("messaging.system", "sqs")
                    .tag("messaging.operation", "process")
                    .tag("messaging.destination", queueName);
            }
        }

        @NewSpan("external-api-call")
        public void traceExternalApiCall(@SpanTag("api.name") String apiName,
                                       @SpanTag("api.operation") String operation,
                                       @SpanTag("customer.document") String customerDocument) {
            if (tracer.currentSpan() != null) {
                tracer.currentSpan()
                    .tag("http.client", "true")
                    .tag("external.api", apiName)
                    .tag("business.domain", "compliance");
            }
        }

        public void addCustomTag(String key, String value) {
            if (tracer.currentSpan() != null) {
                tracer.currentSpan().tag(key, value);
            }
        }

        public void addEvent(String eventName, String description) {
            if (tracer.currentSpan() != null) {
                tracer.currentSpan().event(eventName + ": " + description);
            }
        }
    }
}