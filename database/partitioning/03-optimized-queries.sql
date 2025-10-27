-- =====================================================
-- QUERIES OTIMIZADAS PARA USAR PARTIÇÕES EFICIENTEMENTE
-- =====================================================

-- =====================================================
-- QUERIES PARA ALERTAS
-- =====================================================

-- Query otimizada para buscar alertas por cliente e período
-- Usa partition pruning baseado em created_at
CREATE OR REPLACE FUNCTION get_alerts_by_customer_and_period(
    p_customer_document VARCHAR(20),
    p_start_date DATE,
    p_end_date DATE
)
RETURNS TABLE (
    id UUID,
    customer_document VARCHAR(20),
    scope_start_date DATE,
    scope_end_date DATE,
    status VARCHAR(20),
    process_id VARCHAR(100),
    enrichment_data JSONB,
    created_at TIMESTAMP,
    updated_at TIMESTAMP
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        a.id,
        a.customer_document,
        a.scope_start_date,
        a.scope_end_date,
        a.status,
        a.process_id,
        a.enrichment_data,
        a.created_at,
        a.updated_at
    FROM ms_alert.alerts_partitioned a
    WHERE a.customer_document = p_customer_document
      AND a.created_at >= p_start_date
      AND a.created_at <= p_end_date + '1 day'::INTERVAL
    ORDER BY a.created_at DESC;
END;
$$ LANGUAGE plpgsql;

-- Query otimizada para buscar alertas por status em período específico
CREATE OR REPLACE FUNCTION get_alerts_by_status_and_period(
    p_status VARCHAR(20),
    p_start_date DATE,
    p_end_date DATE
)
RETURNS TABLE (
    id UUID,
    customer_document VARCHAR(20),
    status VARCHAR(20),
    created_at TIMESTAMP
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        a.id,
        a.customer_document,
        a.status,
        a.created_at
    FROM ms_alert.alerts_partitioned a
    WHERE a.status = p_status
      AND a.created_at >= p_start_date
      AND a.created_at <= p_end_date + '1 day'::INTERVAL
    ORDER BY a.created_at DESC;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- QUERIES PARA TRANSAÇÕES
-- =====================================================

-- Query otimizada para KPIs transacionais por cliente e período
CREATE OR REPLACE FUNCTION get_transaction_kpis(
    p_customer_document VARCHAR(20),
    p_start_date DATE,
    p_end_date DATE
)
RETURNS TABLE (
    customer_document VARCHAR(20),
    total_volume DECIMAL(15,2),
    transaction_count BIGINT,
    average_amount DECIMAL(15,2),
    largest_transaction DECIMAL(15,2),
    credit_volume DECIMAL(15,2),
    debit_volume DECIMAL(15,2),
    transfer_volume DECIMAL(15,2),
    unique_counterparties BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        t.customer_document,
        COALESCE(SUM(t.amount), 0) as total_volume,
        COUNT(*) as transaction_count,
        COALESCE(AVG(t.amount), 0) as average_amount,
        COALESCE(MAX(t.amount), 0) as largest_transaction,
        COALESCE(SUM(CASE WHEN t.type = 'CREDIT' THEN t.amount ELSE 0 END), 0) as credit_volume,
        COALESCE(SUM(CASE WHEN t.type = 'DEBIT' THEN t.amount ELSE 0 END), 0) as debit_volume,
        COALESCE(SUM(CASE WHEN t.type IN ('TRANSFER_IN', 'TRANSFER_OUT') THEN t.amount ELSE 0 END), 0) as transfer_volume,
        COUNT(DISTINCT t.counterparty_document) as unique_counterparties
    FROM transactions_partitioned t
    WHERE t.customer_document = p_customer_document
      AND t.transaction_date >= p_start_date::TIMESTAMP
      AND t.transaction_date <= (p_end_date + '1 day'::INTERVAL)::TIMESTAMP
    GROUP BY t.customer_document;
END;
$$ LANGUAGE plpgsql;

-- Query otimizada para principais contrapartes por cliente
CREATE OR REPLACE FUNCTION get_top_counterparties(
    p_customer_document VARCHAR(20),
    p_start_date DATE,
    p_end_date DATE,
    p_limit INTEGER DEFAULT 10
)
RETURNS TABLE (
    counterparty_document VARCHAR(20),
    counterparty_name VARCHAR(255),
    transaction_count BIGINT,
    total_amount DECIMAL(15,2),
    average_amount DECIMAL(15,2),
    last_transaction_date TIMESTAMP
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        t.counterparty_document,
        t.counterparty_name,
        COUNT(*) as transaction_count,
        SUM(t.amount) as total_amount,
        AVG(t.amount) as average_amount,
        MAX(t.transaction_date) as last_transaction_date
    FROM transactions_partitioned t
    WHERE t.customer_document = p_customer_document
      AND t.counterparty_document IS NOT NULL
      AND t.transaction_date >= p_start_date::TIMESTAMP
      AND t.transaction_date <= (p_end_date + '1 day'::INTERVAL)::TIMESTAMP
    GROUP BY t.counterparty_document, t.counterparty_name
    ORDER BY total_amount DESC
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql;

-- Query otimizada para principais transações por cliente
CREATE OR REPLACE FUNCTION get_main_transactions(
    p_customer_document VARCHAR(20),
    p_start_date DATE,
    p_end_date DATE,
    p_limit INTEGER DEFAULT 20
)
RETURNS TABLE (
    id UUID,
    counterparty_document VARCHAR(20),
    counterparty_name VARCHAR(255),
    amount DECIMAL(15,2),
    type VARCHAR(20),
    transaction_date TIMESTAMP,
    description VARCHAR(500),
    channel VARCHAR(50)
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        t.id,
        t.counterparty_document,
        t.counterparty_name,
        t.amount,
        t.type,
        t.transaction_date,
        t.description,
        t.channel
    FROM transactions_partitioned t
    WHERE t.customer_document = p_customer_document
      AND t.transaction_date >= p_start_date::TIMESTAMP
      AND t.transaction_date <= (p_end_date + '1 day'::INTERVAL)::TIMESTAMP
    ORDER BY t.amount DESC, t.transaction_date DESC
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql;

-- Query para análise de padrões transacionais por canal
CREATE OR REPLACE FUNCTION get_transaction_patterns_by_channel(
    p_customer_document VARCHAR(20),
    p_start_date DATE,
    p_end_date DATE
)
RETURNS TABLE (
    channel VARCHAR(50),
    transaction_count BIGINT,
    total_volume DECIMAL(15,2),
    average_amount DECIMAL(15,2),
    peak_hour INTEGER
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        t.channel,
        COUNT(*) as transaction_count,
        SUM(t.amount) as total_volume,
        AVG(t.amount) as average_amount,
        MODE() WITHIN GROUP (ORDER BY EXTRACT(HOUR FROM t.transaction_date))::INTEGER as peak_hour
    FROM transactions_partitioned t
    WHERE t.customer_document = p_customer_document
      AND t.transaction_date >= p_start_date::TIMESTAMP
      AND t.transaction_date <= (p_end_date + '1 day'::INTERVAL)::TIMESTAMP
      AND t.channel IS NOT NULL
    GROUP BY t.channel
    ORDER BY total_volume DESC;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- QUERIES DE MONITORAMENTO E MANUTENÇÃO
-- =====================================================

-- Query para verificar eficiência das partições
CREATE OR REPLACE FUNCTION analyze_partition_efficiency()
RETURNS TABLE (
    table_type VARCHAR(20),
    partition_name TEXT,
    row_count BIGINT,
    size_mb NUMERIC,
    avg_query_time_ms NUMERIC,
    index_usage_ratio NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    WITH partition_stats AS (
        SELECT 
            CASE 
                WHEN schemaname = 'ms_alert' THEN 'alerts'
                ELSE 'transactions'
            END as table_type,
            tablename as partition_name,
            n_tup_ins + n_tup_upd + n_tup_del as total_operations,
            seq_scan + idx_scan as total_scans,
            CASE 
                WHEN seq_scan + idx_scan > 0 
                THEN idx_scan::NUMERIC / (seq_scan + idx_scan) * 100
                ELSE 0
            END as index_usage_ratio
        FROM pg_stat_user_tables
        WHERE schemaname IN ('public', 'ms_alert')
        AND (tablename LIKE 'transactions_%' OR tablename LIKE 'alerts_%')
        AND tablename NOT LIKE '%_partitioned'
    )
    SELECT 
        ps.table_type::VARCHAR(20),
        ps.partition_name,
        COALESCE(pg_stat.n_tup_ins + pg_stat.n_tup_upd + pg_stat.n_tup_del, 0) as row_count,
        ROUND(pg_total_relation_size(pg_class.oid)::NUMERIC / 1024 / 1024, 2) as size_mb,
        0::NUMERIC as avg_query_time_ms, -- Placeholder para métricas de query time
        ps.index_usage_ratio
    FROM partition_stats ps
    JOIN pg_class ON pg_class.relname = ps.partition_name
    LEFT JOIN pg_stat_user_tables pg_stat ON pg_stat.tablename = ps.partition_name
    ORDER BY ps.table_type, ps.partition_name;
END;
$$ LANGUAGE plpgsql;

-- Query para identificar partições que precisam de manutenção
CREATE OR REPLACE FUNCTION identify_maintenance_needed()
RETURNS TABLE (
    partition_name TEXT,
    issue_type VARCHAR(50),
    description TEXT,
    recommended_action TEXT
) AS $$
BEGIN
    RETURN QUERY
    WITH partition_analysis AS (
        SELECT 
            tablename,
            n_tup_ins + n_tup_upd + n_tup_del as total_operations,
            seq_scan,
            idx_scan,
            n_dead_tup,
            last_vacuum,
            last_analyze
        FROM pg_stat_user_tables
        WHERE schemaname IN ('public', 'ms_alert')
        AND (tablename LIKE 'transactions_%' OR tablename LIKE 'alerts_%')
        AND tablename NOT LIKE '%_partitioned'
    )
    SELECT 
        pa.tablename,
        CASE 
            WHEN pa.seq_scan > pa.idx_scan * 2 THEN 'INDEX_USAGE'
            WHEN pa.n_dead_tup > pa.total_operations * 0.1 THEN 'VACUUM_NEEDED'
            WHEN pa.last_analyze < CURRENT_DATE - '7 days'::INTERVAL THEN 'ANALYZE_NEEDED'
            ELSE 'OK'
        END::VARCHAR(50) as issue_type,
        CASE 
            WHEN pa.seq_scan > pa.idx_scan * 2 THEN 'Sequential scans exceeding index scans'
            WHEN pa.n_dead_tup > pa.total_operations * 0.1 THEN 'High number of dead tuples'
            WHEN pa.last_analyze < CURRENT_DATE - '7 days'::INTERVAL THEN 'Statistics outdated'
            ELSE 'Partition is healthy'
        END as description,
        CASE 
            WHEN pa.seq_scan > pa.idx_scan * 2 THEN 'Review and add missing indexes'
            WHEN pa.n_dead_tup > pa.total_operations * 0.1 THEN 'Run VACUUM on partition'
            WHEN pa.last_analyze < CURRENT_DATE - '7 days'::INTERVAL THEN 'Run ANALYZE on partition'
            ELSE 'No action needed'
        END as recommended_action
    FROM partition_analysis pa
    ORDER BY 
        CASE 
            WHEN pa.seq_scan > pa.idx_scan * 2 THEN 1
            WHEN pa.n_dead_tup > pa.total_operations * 0.1 THEN 2
            WHEN pa.last_analyze < CURRENT_DATE - '7 days'::INTERVAL THEN 3
            ELSE 4
        END;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- PROCEDURES DE MANUTENÇÃO AUTOMÁTICA
-- =====================================================

-- Procedure para manutenção automática das partições
CREATE OR REPLACE PROCEDURE maintain_partitions()
LANGUAGE plpgsql AS $$
DECLARE
    partition_record RECORD;
    maintenance_record RECORD;
BEGIN
    -- Log início da manutenção
    RAISE NOTICE 'Starting partition maintenance at %', CURRENT_TIMESTAMP;
    
    -- Executar VACUUM e ANALYZE em partições que precisam
    FOR maintenance_record IN 
        SELECT partition_name, issue_type, recommended_action
        FROM identify_maintenance_needed()
        WHERE issue_type IN ('VACUUM_NEEDED', 'ANALYZE_NEEDED')
    LOOP
        IF maintenance_record.issue_type = 'VACUUM_NEEDED' THEN
            EXECUTE format('VACUUM %I', maintenance_record.partition_name);
            RAISE NOTICE 'Executed VACUUM on %', maintenance_record.partition_name;
        END IF;
        
        IF maintenance_record.issue_type = 'ANALYZE_NEEDED' THEN
            EXECUTE format('ANALYZE %I', maintenance_record.partition_name);
            RAISE NOTICE 'Executed ANALYZE on %', maintenance_record.partition_name;
        END IF;
    END LOOP;
    
    -- Limpar partições antigas
    PERFORM cleanup_old_partitions();
    PERFORM cleanup_old_transaction_partitions();
    
    RAISE NOTICE 'Partition maintenance completed at %', CURRENT_TIMESTAMP;
END;
$$;

COMMENT ON FUNCTION get_alerts_by_customer_and_period(VARCHAR, DATE, DATE) IS 'Query otimizada para buscar alertas usando partition pruning';
COMMENT ON FUNCTION get_transaction_kpis(VARCHAR, DATE, DATE) IS 'Calcula KPIs transacionais usando partições eficientemente';
COMMENT ON FUNCTION get_top_counterparties(VARCHAR, DATE, DATE, INTEGER) IS 'Retorna principais contrapartes usando índices otimizados';
COMMENT ON FUNCTION analyze_partition_efficiency() IS 'Analisa eficiência das partições e uso de índices';
COMMENT ON PROCEDURE maintain_partitions() IS 'Executa manutenção automática das partições (VACUUM, ANALYZE, cleanup)';