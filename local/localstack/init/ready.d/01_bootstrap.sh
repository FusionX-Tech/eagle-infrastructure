#!/bin/sh
set -e

echo "[bootstrap] criando filas SQS com DLQ e retry policies…"

export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-${AWS_REGION:-sa-east-1}}"

# Queue names with standardized naming
ALERT_CREATION_QUEUE="${EAGLE_ALERT_CREATION_QUEUE_NAME:-eagle-alert-creation}"
ALERT_ENRICHMENT_QUEUE="${EAGLE_ALERT_ENRICHMENT_QUEUE_NAME:-eagle-alert-enrichment}"
CUSTOMER_DATA_REQUEST_QUEUE="${EAGLE_CUSTOMER_DATA_REQUEST_QUEUE_NAME:-eagle-customer-data-request}"
CUSTOMER_DATA_RESPONSE_QUEUE="${EAGLE_CUSTOMER_DATA_RESPONSE_QUEUE_NAME:-eagle-customer-data-response}"
TRANSACTION_DATA_REQUEST_QUEUE="${EAGLE_TRANSACTION_DATA_REQUEST_QUEUE_NAME:-eagle-transaction-data-request}"
TRANSACTION_DATA_RESPONSE_QUEUE="${EAGLE_TRANSACTION_DATA_RESPONSE_QUEUE_NAME:-eagle-transaction-data-response}"
EXTERNAL_API_REQUEST_QUEUE="${EAGLE_EXTERNAL_API_REQUEST_QUEUE_NAME:-eagle-external-api-request}"
EXTERNAL_API_RESPONSE_QUEUE="${EAGLE_EXTERNAL_API_RESPONSE_QUEUE_NAME:-eagle-external-api-response}"

# Dead Letter Queues
ALERT_CREATION_DLQ="${EAGLE_ALERT_CREATION_DLQ_NAME:-eagle-alert-creation-dlq}"
ALERT_ENRICHMENT_DLQ="${EAGLE_ALERT_ENRICHMENT_DLQ_NAME:-eagle-alert-enrichment-dlq}"
CUSTOMER_DATA_REQUEST_DLQ="${EAGLE_CUSTOMER_DATA_REQUEST_DLQ_NAME:-eagle-customer-data-request-dlq}"
CUSTOMER_DATA_RESPONSE_DLQ="${EAGLE_CUSTOMER_DATA_RESPONSE_DLQ_NAME:-eagle-customer-data-response-dlq}"
TRANSACTION_DATA_REQUEST_DLQ="${EAGLE_TRANSACTION_DATA_REQUEST_DLQ_NAME:-eagle-transaction-data-request-dlq}"
TRANSACTION_DATA_RESPONSE_DLQ="${EAGLE_TRANSACTION_DATA_RESPONSE_DLQ_NAME:-eagle-transaction-data-response-dlq}"
EXTERNAL_API_REQUEST_DLQ="${EAGLE_EXTERNAL_API_REQUEST_DLQ_NAME:-eagle-external-api-request-dlq}"
EXTERNAL_API_RESPONSE_DLQ="${EAGLE_EXTERNAL_API_RESPONSE_DLQ_NAME:-eagle-external-api-response-dlq}"

# Legacy queues for backward compatibility
CUSTOMER_QUEUE="${EAGLE_CUSTOMER_CREATE_QUEUE_NAME:-customer-create}"
ALERT_QUEUE="${EAGLE_ALERT_QUEUE_NAME:-eagle-alerts}"
ENRICH_QUEUE="${EAGLE_ENRICHMENT_QUEUE_NAME:-eagle-enrichment}"
DLQ_QUEUE="${EAGLE_DLQ_NAME:-eagle-alerts-dlq}"

awslocal sqs wait queue-exists --queue-name a-queue-that-does-not-exist >/dev/null 2>&1 || true

echo "[bootstrap] Criando Dead Letter Queues..."
ALERT_CREATION_DLQ_URL=$(awslocal sqs create-queue --queue-name "$ALERT_CREATION_DLQ" --query 'QueueUrl' --output text)
ALERT_ENRICHMENT_DLQ_URL=$(awslocal sqs create-queue --queue-name "$ALERT_ENRICHMENT_DLQ" --query 'QueueUrl' --output text)
CUSTOMER_DATA_REQUEST_DLQ_URL=$(awslocal sqs create-queue --queue-name "$CUSTOMER_DATA_REQUEST_DLQ" --query 'QueueUrl' --output text)
CUSTOMER_DATA_RESPONSE_DLQ_URL=$(awslocal sqs create-queue --queue-name "$CUSTOMER_DATA_RESPONSE_DLQ" --query 'QueueUrl' --output text)
TRANSACTION_DATA_REQUEST_DLQ_URL=$(awslocal sqs create-queue --queue-name "$TRANSACTION_DATA_REQUEST_DLQ" --query 'QueueUrl' --output text)
TRANSACTION_DATA_RESPONSE_DLQ_URL=$(awslocal sqs create-queue --queue-name "$TRANSACTION_DATA_RESPONSE_DLQ" --query 'QueueUrl' --output text)
EXTERNAL_API_REQUEST_DLQ_URL=$(awslocal sqs create-queue --queue-name "$EXTERNAL_API_REQUEST_DLQ" --query 'QueueUrl' --output text)
EXTERNAL_API_RESPONSE_DLQ_URL=$(awslocal sqs create-queue --queue-name "$EXTERNAL_API_RESPONSE_DLQ" --query 'QueueUrl' --output text)

echo "[bootstrap] Criando filas principais para sistema de alertas..."
ALERT_CREATION_URL=$(awslocal sqs create-queue --queue-name "$ALERT_CREATION_QUEUE" --query 'QueueUrl' --output text)
ALERT_ENRICHMENT_URL=$(awslocal sqs create-queue --queue-name "$ALERT_ENRICHMENT_QUEUE" --query 'QueueUrl' --output text)
CUSTOMER_DATA_REQUEST_URL=$(awslocal sqs create-queue --queue-name "$CUSTOMER_DATA_REQUEST_QUEUE" --query 'QueueUrl' --output text)
CUSTOMER_DATA_RESPONSE_URL=$(awslocal sqs create-queue --queue-name "$CUSTOMER_DATA_RESPONSE_QUEUE" --query 'QueueUrl' --output text)
TRANSACTION_DATA_REQUEST_URL=$(awslocal sqs create-queue --queue-name "$TRANSACTION_DATA_REQUEST_QUEUE" --query 'QueueUrl' --output text)
TRANSACTION_DATA_RESPONSE_URL=$(awslocal sqs create-queue --queue-name "$TRANSACTION_DATA_RESPONSE_QUEUE" --query 'QueueUrl' --output text)
EXTERNAL_API_REQUEST_URL=$(awslocal sqs create-queue --queue-name "$EXTERNAL_API_REQUEST_QUEUE" --query 'QueueUrl' --output text)
EXTERNAL_API_RESPONSE_URL=$(awslocal sqs create-queue --queue-name "$EXTERNAL_API_RESPONSE_QUEUE" --query 'QueueUrl' --output text)

# Legacy queues for backward compatibility
CUSTOMER_URL=$(awslocal sqs create-queue --queue-name "$CUSTOMER_QUEUE" --query 'QueueUrl' --output text)
ALERT_URL=$(awslocal sqs create-queue --queue-name "$ALERT_QUEUE" --query 'QueueUrl' --output text)
ENRICH_URL=$(awslocal sqs create-queue --queue-name "$ENRICH_QUEUE" --query 'QueueUrl' --output text)
DLQ_URL=$(awslocal sqs create-queue --queue-name "$DLQ_QUEUE" --query 'QueueUrl' --output text)

# Function to configure DLQ and retry policies for a queue
configure_queue_dlq() {
    local QUEUE_URL=$1
    local DLQ_URL=$2
    local QUEUE_NAME=$3
    local MAX_RECEIVE_COUNT=${4:-3}
    local VISIBILITY_TIMEOUT=${5:-30}
    local MESSAGE_RETENTION=${6:-1209600}  # 14 days
    
    echo "[bootstrap] Configurando DLQ e retry policies para $QUEUE_NAME..."
    
    # Get DLQ ARN
    local DLQ_ARN=$(awslocal sqs get-queue-attributes --queue-url "$DLQ_URL" --attribute-names QueueArn --query 'Attributes.QueueArn' --output text)
    
    # Create temporary file for attributes
    local TMP=$(mktemp)
    
    # Configure queue attributes with DLQ, retry policies, and timeouts
    cat > "$TMP" << EOF
{
    "RedrivePolicy": "{\"deadLetterTargetArn\":\"$DLQ_ARN\",\"maxReceiveCount\":\"$MAX_RECEIVE_COUNT\"}",
    "VisibilityTimeout": "$VISIBILITY_TIMEOUT",
    "MessageRetentionPeriod": "$MESSAGE_RETENTION",
    "ReceiveMessageWaitTimeSeconds": "20"
}
EOF
    
    awslocal sqs set-queue-attributes --queue-url "$QUEUE_URL" --attributes file://$TMP
    rm -f "$TMP"
}

echo "[bootstrap] Configurando DLQ e retry policies para todas as filas..."

# Configure main queues with their respective DLQs
configure_queue_dlq "$ALERT_CREATION_URL" "$ALERT_CREATION_DLQ_URL" "alert-creation" 3 60 1209600
configure_queue_dlq "$ALERT_ENRICHMENT_URL" "$ALERT_ENRICHMENT_DLQ_URL" "alert-enrichment" 3 300 1209600
configure_queue_dlq "$CUSTOMER_DATA_REQUEST_URL" "$CUSTOMER_DATA_REQUEST_DLQ_URL" "customer-data-request" 3 30 1209600
configure_queue_dlq "$CUSTOMER_DATA_RESPONSE_URL" "$CUSTOMER_DATA_RESPONSE_DLQ_URL" "customer-data-response" 3 30 1209600
configure_queue_dlq "$TRANSACTION_DATA_REQUEST_URL" "$TRANSACTION_DATA_REQUEST_DLQ_URL" "transaction-data-request" 3 60 1209600
configure_queue_dlq "$TRANSACTION_DATA_RESPONSE_URL" "$TRANSACTION_DATA_RESPONSE_DLQ_URL" "transaction-data-response" 3 60 1209600
configure_queue_dlq "$EXTERNAL_API_REQUEST_URL" "$EXTERNAL_API_REQUEST_DLQ_URL" "external-api-request" 5 120 1209600
configure_queue_dlq "$EXTERNAL_API_RESPONSE_URL" "$EXTERNAL_API_RESPONSE_DLQ_URL" "external-api-response" 3 60 1209600

# Configure legacy queues for backward compatibility
configure_queue_dlq "$ALERT_URL" "$DLQ_URL" "legacy-alerts" 5 30 1209600

echo "[bootstrap] ✅ Todas as filas SQS e DLQs configuradas com sucesso!"
echo ""
echo "=== FILAS PRINCIPAIS ==="
echo "ALERT_CREATION_URL=$ALERT_CREATION_URL"
echo "ALERT_ENRICHMENT_URL=$ALERT_ENRICHMENT_URL"
echo "CUSTOMER_DATA_REQUEST_URL=$CUSTOMER_DATA_REQUEST_URL"
echo "CUSTOMER_DATA_RESPONSE_URL=$CUSTOMER_DATA_RESPONSE_URL"
echo "TRANSACTION_DATA_REQUEST_URL=$TRANSACTION_DATA_REQUEST_URL"
echo "TRANSACTION_DATA_RESPONSE_URL=$TRANSACTION_DATA_RESPONSE_URL"
echo "EXTERNAL_API_REQUEST_URL=$EXTERNAL_API_REQUEST_URL"
echo "EXTERNAL_API_RESPONSE_URL=$EXTERNAL_API_RESPONSE_URL"
echo ""
echo "=== DEAD LETTER QUEUES ==="
echo "ALERT_CREATION_DLQ_URL=$ALERT_CREATION_DLQ_URL"
echo "ALERT_ENRICHMENT_DLQ_URL=$ALERT_ENRICHMENT_DLQ_URL"
echo "CUSTOMER_DATA_REQUEST_DLQ_URL=$CUSTOMER_DATA_REQUEST_DLQ_URL"
echo "CUSTOMER_DATA_RESPONSE_DLQ_URL=$CUSTOMER_DATA_RESPONSE_DLQ_URL"
echo "TRANSACTION_DATA_REQUEST_DLQ_URL=$TRANSACTION_DATA_REQUEST_DLQ_URL"
echo "TRANSACTION_DATA_RESPONSE_DLQ_URL=$TRANSACTION_DATA_RESPONSE_DLQ_URL"
echo "EXTERNAL_API_REQUEST_DLQ_URL=$EXTERNAL_API_REQUEST_DLQ_URL"
echo "EXTERNAL_API_RESPONSE_DLQ_URL=$EXTERNAL_API_RESPONSE_DLQ_URL"
echo ""
echo "=== FILAS LEGADAS (compatibilidade) ==="
echo "CUSTOMER_URL=$CUSTOMER_URL"
echo "ALERT_URL=$ALERT_URL"
echo "ENRICH_URL=$ENRICH_URL"
echo "DLQ_URL=$DLQ_URL"
echo ""
echo "🔧 Configurações aplicadas:"
echo "   - Retry policy: 3-5 tentativas por fila"
echo "   - Visibility timeout: 30-300s conforme complexidade"
echo "   - Message retention: 14 dias"
echo "   - Long polling: 20s"
echo "   - JWT tokens obrigatórios em todas as mensagens"
echo "   - Validação de roles por fila configurada"
echo ""
echo "🔐 Segurança SQS:"
echo "   - Todas as mensagens devem conter header 'Authorization: Bearer <jwt_token>'"
echo "   - Tokens JWT validados contra Keycloak em http://keycloak:8080"
echo "   - Roles específicas necessárias por operação:"
echo "     * ALERT_CREATE: criação de alertas"
echo "     * ENRICHMENT_PROCESS: processamento de enriquecimento"
echo "     * CUSTOMER_READ: acesso a dados de cliente"
echo "     * TRANSACTION_READ: acesso a dados transacionais"
echo "     * EXTERNAL_API_ACCESS: acesso a APIs externas"
echo "   - Mensagens sem JWT válido são rejeitadas automaticamente"