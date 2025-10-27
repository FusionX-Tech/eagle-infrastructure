-- =====================================================
-- PARTICIONAMENTO DA TABELA TRANSACTIONS POR PERÍODO
-- =====================================================

-- Criar nova tabela particionada para transactions
CREATE TABLE IF NOT EXISTS transactions_partitioned (
    id UUID NOT NULL,
    customer_document VARCHAR(20) NOT NULL,
    counterparty_document VARCHAR(20),
    counterparty_name VARCHAR(255),
    amount DECIMAL(15,2) NOT NULL,
    type VARCHAR(20) NOT NULL,
    transaction_date TIMESTAMP NOT NULL,
    description VARCHAR(500),
    channel VARCHAR(50),
    source_system VARCHAR(100),
    transaction_id VARCHAR(50),
    account_number VARCHAR(20),
    branch_code VARCHAR(10),
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP,
    PRIMARY KEY (id, transaction_date)
) PARTITION BY RANGE (transaction_date);

-- Criar índices na tabela particionada
CREATE INDEX IF NOT EXISTS idx_trans_part_customer_doc ON transactions_partitioned (customer_document);
CREATE INDEX IF NOT EXISTS idx_trans_part_customer_date ON transactions_partitioned (customer_document, transaction_date);
CREATE INDEX IF NOT EXISTS idx_trans_part_counterparty ON transactions_partitioned (counterparty_document);
CREATE INDEX IF NOT EXISTS idx_trans_part_type ON transactions_partitioned (type);
CREATE INDEX IF NOT EXISTS idx_trans_part_amount ON transactions_partitioned (amount);
CREATE INDEX IF NOT EXISTS idx_trans_part_channel ON transactions_partitioned (channel);
CREATE INDEX IF NOT EXISTS idx_trans_part_transaction_id ON transactions_partitioned (transaction_id);

-- Criar partições mensais para os últimos 24 meses e próximos 12 meses
DO $$
DECLARE
    start_date DATE;
    end_date DATE;
    partition_name TEXT;
    current_month DATE;
BEGIN
    -- Começar 24 meses atrás
    current_month := DATE_TRUNC('month', CURRENT_DATE - '24 months'::INTERVAL);
    
    -- Criar partições para 36 meses (24 passados + 12 futuros)
    FOR i IN 0..35 LOOP
        start_date := current_month + (i || ' months')::INTERVAL;
        end_date := start_date + '1 month'::INTERVAL;
        partition_name := 'transactions_' || TO_CHAR(start_date, 'YYYY_MM');
        
        EXECUTE format('
            CREATE TABLE IF NOT EXISTS %I PARTITION OF transactions_partitioned
            FOR VALUES FROM (%L) TO (%L)',
            partition_name, start_date, end_date
        );
        
        -- Criar índices específicos para cada partição (otimizados para queries frequentes)
        EXECUTE format('
            CREATE INDEX IF NOT EXISTS %I ON %I (customer_document, transaction_date DESC)',
            'idx_' || partition_name || '_customer_date_desc', partition_name
        );
        
        EXECUTE format('
            CREATE INDEX IF NOT EXISTS %I ON %I (customer_document, type, amount)',
            'idx_' || partition_name || '_customer_type_amount', partition_name
        );
        
        EXECUTE format('
            CREATE INDEX IF NOT EXISTS %I ON %I (counterparty_document, amount DESC)',
            'idx_' || partition_name || '_counterparty_amount', partition_name
        );
        
        -- Índice para análise de KPIs por período
        EXECUTE format('
            CREATE INDEX IF NOT EXISTS %I ON %I (customer_document, type) INCLUDE (amount)',
            'idx_' || partition_name || '_kpi_analysis', partition_name
        );
    END LOOP;
END $$;

-- Criar função para criação automática de partições futuras
CREATE OR REPLACE FUNCTION create_monthly_transaction_partition()
RETURNS TRIGGER AS $$
DECLARE
    partition_date DATE;
    partition_name TEXT;
    start_date DATE;
    end_date DATE;
BEGIN
    -- Extrair o mês da data da transação
    partition_date := DATE_TRUNC('month', NEW.transaction_date);
    partition_name := 'transactions_' || TO_CHAR(partition_date, 'YYYY_MM');
    start_date := partition_date;
    end_date := partition_date + '1 month'::INTERVAL;
    
    -- Verificar se a partição já existe
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'public' 
        AND table_name = partition_name
    ) THEN
        -- Criar nova partição
        EXECUTE format('
            CREATE TABLE %I PARTITION OF transactions_partitioned
            FOR VALUES FROM (%L) TO (%L)',
            partition_name, start_date, end_date
        );
        
        -- Criar índices para a nova partição
        EXECUTE format('
            CREATE INDEX %I ON %I (customer_document, transaction_date DESC)',
            'idx_' || partition_name || '_customer_date_desc', partition_name
        );
        
        EXECUTE format('
            CREATE INDEX %I ON %I (customer_document, type, amount)',
            'idx_' || partition_name || '_customer_type_amount', partition_name
        );
        
        EXECUTE format('
            CREATE INDEX %I ON %I (counterparty_document, amount DESC)',
            'idx_' || partition_name || '_counterparty_amount', partition_name
        );
        
        EXECUTE format('
            CREATE INDEX %I ON %I (customer_document, type) INCLUDE (amount)',
            'idx_' || partition_name || '_kpi_analysis', partition_name
        );
        
        RAISE NOTICE 'Created transaction partition: %', partition_name;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Criar trigger para criação automática de partições
DROP TRIGGER IF EXISTS trigger_create_transaction_partition ON transactions_partitioned;
CREATE TRIGGER trigger_create_transaction_partition
    BEFORE INSERT ON transactions_partitioned
    FOR EACH ROW EXECUTE FUNCTION create_monthly_transaction_partition();

-- Criar views otimizadas para diferentes tipos de consulta
CREATE OR REPLACE VIEW transactions_view AS
SELECT 
    id,
    customer_document,
    counterparty_document,
    counterparty_name,
    amount,
    type,
    transaction_date,
    description,
    channel,
    source_system,
    transaction_id,
    account_number,
    branch_code,
    created_at,
    updated_at
FROM transactions_partitioned;

-- View para análise de KPIs (últimos 12 meses)
CREATE OR REPLACE VIEW transactions_kpi_view AS
SELECT 
    customer_document,
    type,
    counterparty_document,
    counterparty_name,
    amount,
    transaction_date,
    channel
FROM transactions_partitioned
WHERE transaction_date >= DATE_TRUNC('month', CURRENT_DATE - '12 months'::INTERVAL);

-- View para principais contrapartes (últimos 6 meses)
CREATE OR REPLACE VIEW top_counterparties_view AS
SELECT 
    customer_document,
    counterparty_document,
    counterparty_name,
    COUNT(*) as transaction_count,
    SUM(amount) as total_amount,
    AVG(amount) as avg_amount,
    MAX(transaction_date) as last_transaction_date
FROM transactions_partitioned
WHERE transaction_date >= DATE_TRUNC('month', CURRENT_DATE - '6 months'::INTERVAL)
    AND counterparty_document IS NOT NULL
GROUP BY customer_document, counterparty_document, counterparty_name;

-- Função para migrar dados da tabela original (se existir)
CREATE OR REPLACE FUNCTION migrate_transactions_to_partitioned()
RETURNS INTEGER AS $$
DECLARE
    migrated_count INTEGER := 0;
BEGIN
    -- Verificar se a tabela original existe
    IF EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'public' 
        AND table_name = 'transactions'
    ) THEN
        -- Migrar dados em lotes para evitar locks longos
        INSERT INTO transactions_partitioned 
        SELECT * FROM transactions
        ON CONFLICT (id, transaction_date) DO NOTHING;
        
        GET DIAGNOSTICS migrated_count = ROW_COUNT;
        
        RAISE NOTICE 'Migrated % transaction records to partitioned table', migrated_count;
    END IF;
    
    RETURN migrated_count;
END;
$$ LANGUAGE plpgsql;

-- Função para limpeza de partições antigas (manter apenas 36 meses)
CREATE OR REPLACE FUNCTION cleanup_old_transaction_partitions()
RETURNS INTEGER AS $$
DECLARE
    partition_record RECORD;
    cutoff_date DATE;
    dropped_count INTEGER := 0;
BEGIN
    -- Data limite: 36 meses atrás
    cutoff_date := DATE_TRUNC('month', CURRENT_DATE - '36 months'::INTERVAL);
    
    -- Buscar partições antigas
    FOR partition_record IN
        SELECT schemaname, tablename
        FROM pg_tables
        WHERE schemaname = 'public'
        AND tablename LIKE 'transactions_____'
        AND tablename < 'transactions_' || TO_CHAR(cutoff_date, 'YYYY_MM')
    LOOP
        -- Dropar partição antiga
        EXECUTE format('DROP TABLE IF EXISTS %I.%I', 
                      partition_record.schemaname, 
                      partition_record.tablename);
        
        dropped_count := dropped_count + 1;
        RAISE NOTICE 'Dropped old transaction partition: %', partition_record.tablename;
    END LOOP;
    
    RETURN dropped_count;
END;
$$ LANGUAGE plpgsql;

-- Função para estatísticas de partições
CREATE OR REPLACE FUNCTION get_partition_statistics()
RETURNS TABLE (
    partition_name TEXT,
    row_count BIGINT,
    size_mb NUMERIC,
    min_date DATE,
    max_date DATE
) AS $$
DECLARE
    partition_record RECORD;
BEGIN
    FOR partition_record IN
        SELECT schemaname, tablename
        FROM pg_tables
        WHERE schemaname IN ('public', 'ms_alert')
        AND (tablename LIKE 'transactions_%' OR tablename LIKE 'alerts_%')
        AND tablename NOT LIKE '%_partitioned'
        ORDER BY tablename
    LOOP
        RETURN QUERY
        EXECUTE format('
            SELECT 
                %L::TEXT as partition_name,
                COUNT(*)::BIGINT as row_count,
                ROUND(pg_total_relation_size(%L)::NUMERIC / 1024 / 1024, 2) as size_mb,
                MIN(CASE 
                    WHEN %L LIKE ''transactions_%%'' THEN transaction_date::DATE
                    ELSE created_at::DATE
                END) as min_date,
                MAX(CASE 
                    WHEN %L LIKE ''transactions_%%'' THEN transaction_date::DATE
                    ELSE created_at::DATE
                END) as max_date
            FROM %I.%I',
            partition_record.tablename,
            partition_record.schemaname || '.' || partition_record.tablename,
            partition_record.tablename,
            partition_record.tablename,
            partition_record.schemaname,
            partition_record.tablename
        );
    END LOOP;
END;
$$ LANGUAGE plpgsql;

COMMENT ON TABLE transactions_partitioned IS 'Tabela de transações particionada por mês para melhor performance em consultas temporais';
COMMENT ON FUNCTION create_monthly_transaction_partition() IS 'Função para criação automática de partições mensais de transações';
COMMENT ON FUNCTION cleanup_old_transaction_partitions() IS 'Função para limpeza de partições antigas de transações (>36 meses)';
COMMENT ON VIEW transactions_kpi_view IS 'View otimizada para cálculo de KPIs dos últimos 12 meses';
COMMENT ON VIEW top_counterparties_view IS 'View pré-agregada das principais contrapartes dos últimos 6 meses';