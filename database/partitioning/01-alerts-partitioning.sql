-- =====================================================
-- PARTICIONAMENTO DA TABELA ALERTS POR DATA
-- =====================================================

-- Criar nova tabela particionada para alerts
CREATE TABLE IF NOT EXISTS ms_alert.alerts_partitioned (
    id UUID NOT NULL,
    customer_document VARCHAR(20) NOT NULL,
    scope_start_date DATE NOT NULL,
    scope_end_date DATE NOT NULL,
    status VARCHAR(20) NOT NULL,
    process_id VARCHAR(100),
    enrichment_data JSONB,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id, created_at)
) PARTITION BY RANGE (created_at);

-- Criar índices na tabela particionada
CREATE INDEX IF NOT EXISTS idx_alerts_part_customer_doc ON ms_alert.alerts_partitioned (customer_document);
CREATE INDEX IF NOT EXISTS idx_alerts_part_status ON ms_alert.alerts_partitioned (status);
CREATE INDEX IF NOT EXISTS idx_alerts_part_process_id ON ms_alert.alerts_partitioned (process_id);
CREATE INDEX IF NOT EXISTS idx_alerts_part_scope_dates ON ms_alert.alerts_partitioned (scope_start_date, scope_end_date);
CREATE INDEX IF NOT EXISTS idx_alerts_part_enrichment_gin ON ms_alert.alerts_partitioned USING GIN (enrichment_data);

-- Criar partições mensais para os próximos 12 meses
DO $$
DECLARE
    start_date DATE;
    end_date DATE;
    partition_name TEXT;
    current_month DATE;
BEGIN
    -- Começar do primeiro dia do mês atual
    current_month := DATE_TRUNC('month', CURRENT_DATE);
    
    -- Criar partições para os próximos 12 meses
    FOR i IN 0..11 LOOP
        start_date := current_month + (i || ' months')::INTERVAL;
        end_date := start_date + '1 month'::INTERVAL;
        partition_name := 'alerts_' || TO_CHAR(start_date, 'YYYY_MM');
        
        EXECUTE format('
            CREATE TABLE IF NOT EXISTS ms_alert.%I PARTITION OF ms_alert.alerts_partitioned
            FOR VALUES FROM (%L) TO (%L)',
            partition_name, start_date, end_date
        );
        
        -- Criar índices específicos para cada partição
        EXECUTE format('
            CREATE INDEX IF NOT EXISTS %I ON ms_alert.%I (customer_document, created_at)',
            'idx_' || partition_name || '_customer_created', partition_name
        );
        
        EXECUTE format('
            CREATE INDEX IF NOT EXISTS %I ON ms_alert.%I (status, created_at)',
            'idx_' || partition_name || '_status_created', partition_name
        );
    END LOOP;
END $$;

-- Criar função para criação automática de partições futuras
CREATE OR REPLACE FUNCTION ms_alert.create_monthly_partition()
RETURNS TRIGGER AS $$
DECLARE
    partition_date DATE;
    partition_name TEXT;
    start_date DATE;
    end_date DATE;
BEGIN
    -- Extrair o mês da data de criação
    partition_date := DATE_TRUNC('month', NEW.created_at);
    partition_name := 'alerts_' || TO_CHAR(partition_date, 'YYYY_MM');
    start_date := partition_date;
    end_date := partition_date + '1 month'::INTERVAL;
    
    -- Verificar se a partição já existe
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'ms_alert' 
        AND table_name = partition_name
    ) THEN
        -- Criar nova partição
        EXECUTE format('
            CREATE TABLE ms_alert.%I PARTITION OF ms_alert.alerts_partitioned
            FOR VALUES FROM (%L) TO (%L)',
            partition_name, start_date, end_date
        );
        
        -- Criar índices para a nova partição
        EXECUTE format('
            CREATE INDEX %I ON ms_alert.%I (customer_document, created_at)',
            'idx_' || partition_name || '_customer_created', partition_name
        );
        
        EXECUTE format('
            CREATE INDEX %I ON ms_alert.%I (status, created_at)',
            'idx_' || partition_name || '_status_created', partition_name
        );
        
        RAISE NOTICE 'Created partition: %', partition_name;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Criar trigger para criação automática de partições
DROP TRIGGER IF EXISTS trigger_create_alert_partition ON ms_alert.alerts_partitioned;
CREATE TRIGGER trigger_create_alert_partition
    BEFORE INSERT ON ms_alert.alerts_partitioned
    FOR EACH ROW EXECUTE FUNCTION ms_alert.create_monthly_partition();

-- Criar view para facilitar queries sem especificar partições
CREATE OR REPLACE VIEW ms_alert.alerts_view AS
SELECT 
    id,
    customer_document,
    scope_start_date,
    scope_end_date,
    status,
    process_id,
    enrichment_data,
    created_at,
    updated_at
FROM ms_alert.alerts_partitioned;

-- Função para migrar dados da tabela original (se existir)
CREATE OR REPLACE FUNCTION ms_alert.migrate_alerts_to_partitioned()
RETURNS INTEGER AS $$
DECLARE
    migrated_count INTEGER := 0;
BEGIN
    -- Verificar se a tabela original existe
    IF EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'ms_alert' 
        AND table_name = 'alerts'
    ) THEN
        -- Migrar dados
        INSERT INTO ms_alert.alerts_partitioned 
        SELECT * FROM ms_alert.alerts
        ON CONFLICT (id, created_at) DO NOTHING;
        
        GET DIAGNOSTICS migrated_count = ROW_COUNT;
        
        RAISE NOTICE 'Migrated % records to partitioned table', migrated_count;
    END IF;
    
    RETURN migrated_count;
END;
$$ LANGUAGE plpgsql;

-- Função para limpeza de partições antigas (manter apenas 24 meses)
CREATE OR REPLACE FUNCTION ms_alert.cleanup_old_partitions()
RETURNS INTEGER AS $$
DECLARE
    partition_record RECORD;
    cutoff_date DATE;
    dropped_count INTEGER := 0;
BEGIN
    -- Data limite: 24 meses atrás
    cutoff_date := DATE_TRUNC('month', CURRENT_DATE - '24 months'::INTERVAL);
    
    -- Buscar partições antigas
    FOR partition_record IN
        SELECT schemaname, tablename
        FROM pg_tables
        WHERE schemaname = 'ms_alert'
        AND tablename LIKE 'alerts_____'
        AND tablename < 'alerts_' || TO_CHAR(cutoff_date, 'YYYY_MM')
    LOOP
        -- Dropar partição antiga
        EXECUTE format('DROP TABLE IF EXISTS %I.%I', 
                      partition_record.schemaname, 
                      partition_record.tablename);
        
        dropped_count := dropped_count + 1;
        RAISE NOTICE 'Dropped old partition: %', partition_record.tablename;
    END LOOP;
    
    RETURN dropped_count;
END;
$$ LANGUAGE plpgsql;

COMMENT ON TABLE ms_alert.alerts_partitioned IS 'Tabela de alertas particionada por mês para melhor performance';
COMMENT ON FUNCTION ms_alert.create_monthly_partition() IS 'Função para criação automática de partições mensais';
COMMENT ON FUNCTION ms_alert.cleanup_old_partitions() IS 'Função para limpeza de partições antigas (>24 meses)';