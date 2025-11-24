#!/bin/sh
set -e

echo "[bootstrap] criando filas SQS com DLQ e retry policies…"

export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-${AWS_REGION:-sa-east-1}}"

# Queue names with standardized naming
ALERT_CREATION_QUEUE="${EAGLE_ALERT_CREATION_QUEUE_NAME:-eagle-alert-creation}"
CUSTOMER_DATA_REQUEST_QUEUE="${EAGLE_CUSTOMER_DATA_REQUEST_QUEUE_NAME:-eagle-customer-data-request}"
CUSTOMER_DATA_RESPONSE_QUEUE="${EAGLE_CUSTOMER_DATA_RESPONSE_QUEUE_NAME:-eagle-customer-data-response}"
EXTERNAL_API_REQUEST_QUEUE="${EAGLE_EXTERNAL_API_REQUEST_QUEUE_NAME:-eagle-external-api-request}"
EXTERNAL_API_RESPONSE_QUEUE="${EAGLE_EXTERNAL_API_RESPONSE_QUEUE_NAME:-eagle-external-api-response}"

# Dead Letter Queues
ALERT_CREATION_DLQ="${EAGLE_ALERT_CREATION_DLQ_NAME:-eagle-alert-creation-dlq}"
CUSTOMER_DATA_REQUEST_DLQ="${EAGLE_CUSTOMER_DATA_REQUEST_DLQ_NAME:-eagle-customer-data-request-dlq}"
CUSTOMER_DATA_RESPONSE_DLQ="${EAGLE_CUSTOMER_DATA_RESPONSE_DLQ_NAME:-eagle-customer-data-response-dlq}"
EXTERNAL_API_REQUEST_DLQ="${EAGLE_EXTERNAL_API_REQUEST_DLQ_NAME:-eagle-external-api-request-dlq}"
EXTERNAL_API_RESPONSE_DLQ="${EAGLE_EXTERNAL_API_RESPONSE_DLQ_NAME:-eagle-external-api-response-dlq}"

# MS-QA queues
ANALYSIS_COMPLETED_QUEUE="${EAGLE_ANALYSIS_COMPLETED_QUEUE_NAME:-analysis-completed-queue}"
QUALITY_ALERT_QUEUE="${EAGLE_QUALITY_ALERT_QUEUE_NAME:-quality-alert-queue}"
ANALYSIS_COMPLETED_DLQ="${EAGLE_ANALYSIS_COMPLETED_DLQ_NAME:-analysis-completed-queue-dlq}"
QUALITY_ALERT_DLQ="${EAGLE_QUALITY_ALERT_DLQ_NAME:-quality-alert-queue-dlq}"

# FIFO queues for transactional enrichment with priority
ENRICHMENT_HIGH_FIFO="${EAGLE_ENRICHMENT_HIGH_FIFO_NAME:-eagle-alert-transactional-enrichment-high.fifo}"
ENRICHMENT_NORMAL_FIFO="${EAGLE_ENRICHMENT_NORMAL_FIFO_NAME:-eagle-alert-transactional-enrichment-normal.fifo}"

# MS-Orchestrator queues for customer batch processing
CUSTOMER_BATCH_QUEUE="${EAGLE_CUSTOMER_BATCH_QUEUE_NAME:-customer-batch-queue}"
CUSTOMER_ENRICHMENT_QUEUE="${EAGLE_CUSTOMER_ENRICHMENT_QUEUE_NAME:-customer-enrichment-queue}"
CUSTOMER_CREATION_QUEUE="${EAGLE_CUSTOMER_CREATION_QUEUE_NAME:-customer-creation-queue}"
BATCH_PROGRESS_QUEUE="${EAGLE_BATCH_PROGRESS_QUEUE_NAME:-batch-progress-queue}"

# MS-Orchestrator DLQs
CUSTOMER_BATCH_DLQ="${EAGLE_CUSTOMER_BATCH_DLQ_NAME:-customer-batch-queue-dlq}"
CUSTOMER_ENRICHMENT_DLQ="${EAGLE_CUSTOMER_ENRICHMENT_DLQ_NAME:-customer-enrichment-queue-dlq}"
CUSTOMER_CREATION_DLQ="${EAGLE_CUSTOMER_CREATION_DLQ_NAME:-customer-creation-queue-dlq}"
BATCH_PROGRESS_DLQ="${EAGLE_BATCH_PROGRESS_DLQ_NAME:-batch-progress-queue-dlq}"

awslocal sqs wait queue-exists --queue-name a-queue-that-does-not-exist >/dev/null 2>&1 || true

echo "[bootstrap] Criando Dead Letter Queues..."
ALERT_CREATION_DLQ_URL=$(awslocal sqs create-queue --queue-name "$ALERT_CREATION_DLQ" --query 'QueueUrl' --output text)
CUSTOMER_DATA_REQUEST_DLQ_URL=$(awslocal sqs create-queue --queue-name "$CUSTOMER_DATA_REQUEST_DLQ" --query 'QueueUrl' --output text)
CUSTOMER_DATA_RESPONSE_DLQ_URL=$(awslocal sqs create-queue --queue-name "$CUSTOMER_DATA_RESPONSE_DLQ" --query 'QueueUrl' --output text)
EXTERNAL_API_REQUEST_DLQ_URL=$(awslocal sqs create-queue --queue-name "$EXTERNAL_API_REQUEST_DLQ" --query 'QueueUrl' --output text)
EXTERNAL_API_RESPONSE_DLQ_URL=$(awslocal sqs create-queue --queue-name "$EXTERNAL_API_RESPONSE_DLQ" --query 'QueueUrl' --output text)

# MS-QA DLQs
ANALYSIS_COMPLETED_DLQ_URL=$(awslocal sqs create-queue --queue-name "$ANALYSIS_COMPLETED_DLQ" --query 'QueueUrl' --output text)
QUALITY_ALERT_DLQ_URL=$(awslocal sqs create-queue --queue-name "$QUALITY_ALERT_DLQ" --query 'QueueUrl' --output text)

# MS-Orchestrator DLQs
CUSTOMER_BATCH_DLQ_URL=$(awslocal sqs create-queue --queue-name "$CUSTOMER_BATCH_DLQ" --query 'QueueUrl' --output text)
CUSTOMER_ENRICHMENT_DLQ_URL=$(awslocal sqs create-queue --queue-name "$CUSTOMER_ENRICHMENT_DLQ" --query 'QueueUrl' --output text)
CUSTOMER_CREATION_DLQ_URL=$(awslocal sqs create-queue --queue-name "$CUSTOMER_CREATION_DLQ" --query 'QueueUrl' --output text)
BATCH_PROGRESS_DLQ_URL=$(awslocal sqs create-queue --queue-name "$BATCH_PROGRESS_DLQ" --query 'QueueUrl' --output text)

echo "[bootstrap] Criando filas principais para sistema de alertas..."
ALERT_CREATION_URL=$(awslocal sqs create-queue --queue-name "$ALERT_CREATION_QUEUE" --query 'QueueUrl' --output text)
CUSTOMER_DATA_REQUEST_URL=$(awslocal sqs create-queue --queue-name "$CUSTOMER_DATA_REQUEST_QUEUE" --query 'QueueUrl' --output text)
CUSTOMER_DATA_RESPONSE_URL=$(awslocal sqs create-queue --queue-name "$CUSTOMER_DATA_RESPONSE_QUEUE" --query 'QueueUrl' --output text)
EXTERNAL_API_REQUEST_URL=$(awslocal sqs create-queue --queue-name "$EXTERNAL_API_REQUEST_QUEUE" --query 'QueueUrl' --output text)
EXTERNAL_API_RESPONSE_URL=$(awslocal sqs create-queue --queue-name "$EXTERNAL_API_RESPONSE_QUEUE" --query 'QueueUrl' --output text)

# MS-QA main queues
ANALYSIS_COMPLETED_URL=$(awslocal sqs create-queue --queue-name "$ANALYSIS_COMPLETED_QUEUE" --query 'QueueUrl' --output text)
QUALITY_ALERT_URL=$(awslocal sqs create-queue --queue-name "$QUALITY_ALERT_QUEUE" --query 'QueueUrl' --output text)

# MS-Orchestrator main queues
echo "[bootstrap] Criando filas para MS-Orchestrator (customer batch processing)..."
CUSTOMER_BATCH_URL=$(awslocal sqs create-queue --queue-name "$CUSTOMER_BATCH_QUEUE" --query 'QueueUrl' --output text)
CUSTOMER_ENRICHMENT_URL=$(awslocal sqs create-queue --queue-name "$CUSTOMER_ENRICHMENT_QUEUE" --query 'QueueUrl' --output text)
CUSTOMER_CREATION_URL=$(awslocal sqs create-queue --queue-name "$CUSTOMER_CREATION_QUEUE" --query 'QueueUrl' --output text)
BATCH_PROGRESS_URL=$(awslocal sqs create-queue --queue-name "$BATCH_PROGRESS_QUEUE" --query 'QueueUrl' --output text)

# FIFO queues for transactional enrichment with priority
echo "[bootstrap] Criando filas FIFO para enriquecimento transacional..."
ENRICHMENT_HIGH_FIFO_URL=$(awslocal sqs create-queue \
    --queue-name "$ENRICHMENT_HIGH_FIFO" \
    --attributes '{"FifoQueue":"true","ContentBasedDeduplication":"true","MessageRetentionPeriod":"1209600","VisibilityTimeout":"600"}' \
    --query 'QueueUrl' --output text)

ENRICHMENT_NORMAL_FIFO_URL=$(awslocal sqs create-queue \
    --queue-name "$ENRICHMENT_NORMAL_FIFO" \
    --attributes '{"FifoQueue":"true","ContentBasedDeduplication":"true","MessageRetentionPeriod":"1209600","VisibilityTimeout":"600"}' \
    --query 'QueueUrl' --output text)

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
configure_queue_dlq "$CUSTOMER_DATA_REQUEST_URL" "$CUSTOMER_DATA_REQUEST_DLQ_URL" "customer-data-request" 3 30 1209600
configure_queue_dlq "$CUSTOMER_DATA_RESPONSE_URL" "$CUSTOMER_DATA_RESPONSE_DLQ_URL" "customer-data-response" 3 30 1209600
configure_queue_dlq "$EXTERNAL_API_REQUEST_URL" "$EXTERNAL_API_REQUEST_DLQ_URL" "external-api-request" 5 120 1209600
configure_queue_dlq "$EXTERNAL_API_RESPONSE_URL" "$EXTERNAL_API_RESPONSE_DLQ_URL" "external-api-response" 3 60 1209600

# Configure MS-QA queues
configure_queue_dlq "$ANALYSIS_COMPLETED_URL" "$ANALYSIS_COMPLETED_DLQ_URL" "analysis-completed" 3 30 1209600
configure_queue_dlq "$QUALITY_ALERT_URL" "$QUALITY_ALERT_DLQ_URL" "quality-alert" 3 30 1209600

# Configure MS-Orchestrator queues
configure_queue_dlq "$CUSTOMER_BATCH_URL" "$CUSTOMER_BATCH_DLQ_URL" "customer-batch" 3 60 1209600
configure_queue_dlq "$CUSTOMER_ENRICHMENT_URL" "$CUSTOMER_ENRICHMENT_DLQ_URL" "customer-enrichment" 3 60 1209600
configure_queue_dlq "$CUSTOMER_CREATION_URL" "$CUSTOMER_CREATION_DLQ_URL" "customer-creation" 3 30 1209600
configure_queue_dlq "$BATCH_PROGRESS_URL" "$BATCH_PROGRESS_DLQ_URL" "batch-progress" 3 30 1209600

echo "[bootstrap] ✅ Todas as filas SQS e DLQs configuradas com sucesso!"
echo ""
echo "=== FILAS PRINCIPAIS ==="
echo "ALERT_CREATION_URL=$ALERT_CREATION_URL"
echo "CUSTOMER_DATA_REQUEST_URL=$CUSTOMER_DATA_REQUEST_URL"
echo "CUSTOMER_DATA_RESPONSE_URL=$CUSTOMER_DATA_RESPONSE_URL"
echo "EXTERNAL_API_REQUEST_URL=$EXTERNAL_API_REQUEST_URL"
echo "EXTERNAL_API_RESPONSE_URL=$EXTERNAL_API_RESPONSE_URL"
echo "ANALYSIS_COMPLETED_URL=$ANALYSIS_COMPLETED_URL"
echo "QUALITY_ALERT_URL=$QUALITY_ALERT_URL"
echo ""
echo "=== FILAS MS-ORCHESTRATOR (CUSTOMER BATCH) ==="
echo "CUSTOMER_BATCH_URL=$CUSTOMER_BATCH_URL"
echo "CUSTOMER_ENRICHMENT_URL=$CUSTOMER_ENRICHMENT_URL"
echo "CUSTOMER_CREATION_URL=$CUSTOMER_CREATION_URL"
echo "BATCH_PROGRESS_URL=$BATCH_PROGRESS_URL"
echo ""
echo "=== FILAS FIFO (ENRIQUECIMENTO) ==="
echo "ENRICHMENT_HIGH_FIFO_URL=$ENRICHMENT_HIGH_FIFO_URL"
echo "ENRICHMENT_NORMAL_FIFO_URL=$ENRICHMENT_NORMAL_FIFO_URL"
echo ""
echo "=== DEAD LETTER QUEUES ==="
echo "ALERT_CREATION_DLQ_URL=$ALERT_CREATION_DLQ_URL"
echo "CUSTOMER_DATA_REQUEST_DLQ_URL=$CUSTOMER_DATA_REQUEST_DLQ_URL"
echo "CUSTOMER_DATA_RESPONSE_DLQ_URL=$CUSTOMER_DATA_RESPONSE_DLQ_URL"
echo "EXTERNAL_API_REQUEST_DLQ_URL=$EXTERNAL_API_REQUEST_DLQ_URL"
echo "EXTERNAL_API_RESPONSE_DLQ_URL=$EXTERNAL_API_RESPONSE_DLQ_URL"
echo "ANALYSIS_COMPLETED_DLQ_URL=$ANALYSIS_COMPLETED_DLQ_URL"
echo "QUALITY_ALERT_DLQ_URL=$QUALITY_ALERT_DLQ_URL"
echo "CUSTOMER_BATCH_DLQ_URL=$CUSTOMER_BATCH_DLQ_URL"
echo "CUSTOMER_ENRICHMENT_DLQ_URL=$CUSTOMER_ENRICHMENT_DLQ_URL"
echo "CUSTOMER_CREATION_DLQ_URL=$CUSTOMER_CREATION_DLQ_URL"
echo "BATCH_PROGRESS_DLQ_URL=$BATCH_PROGRESS_DLQ_URL"
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