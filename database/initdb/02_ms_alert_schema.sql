\connect ms_alert;

-- 1) Schema e search_path (somente para esta sessão)
CREATE SCHEMA IF NOT EXISTS ms_alert AUTHORIZATION CURRENT_USER;
SET search_path TO ms_alert, public;

-- 2) Extensão UUID neste DB
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 3) Tabela principal de alertas (particionada)
CREATE TABLE IF NOT EXISTS ms_alert.alerts_partitioned (
  id                  uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  customer_document   varchar(20) NOT NULL,             -- documento do cliente (CPF/CNPJ)
  scope_start_date    date NOT NULL,                    -- data de início do escopo de análise
  scope_end_date      date NOT NULL,                    -- data de fim do escopo de análise
  status              varchar(20) NOT NULL DEFAULT 'CREATED', -- CREATED|ENRICHING|COMPLETED|FAILED|CANCELLED
  process_id          varchar(100),                     -- ID do processo de orquestração
  enrichment_data     text,                             -- dados de enriquecimento em JSON
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),
  
  -- Constraints
  CONSTRAINT chk_alerts_scope_dates CHECK (scope_end_date >= scope_start_date),
  CONSTRAINT chk_alerts_status CHECK (status IN ('CREATED', 'ENRICHING', 'COMPLETED', 'FAILED', 'CANCELLED')),
  CONSTRAINT chk_alerts_customer_document CHECK (LENGTH(customer_document) >= 11)
);

-- 4) Índices otimizados para a tabela particionada
CREATE INDEX IF NOT EXISTS idx_alerts_part_customer_doc ON ms_alert.alerts_partitioned (customer_document);
CREATE INDEX IF NOT EXISTS idx_alerts_part_status ON ms_alert.alerts_partitioned (status);
CREATE INDEX IF NOT EXISTS idx_alerts_part_process_id ON ms_alert.alerts_partitioned (process_id);
CREATE INDEX IF NOT EXISTS idx_alerts_part_scope_dates ON ms_alert.alerts_partitioned (scope_start_date, scope_end_date);
CREATE INDEX IF NOT EXISTS idx_alerts_part_customer_status ON ms_alert.alerts_partitioned (customer_document, status);
CREATE INDEX IF NOT EXISTS idx_alerts_part_created_at ON ms_alert.alerts_partitioned (created_at);
CREATE INDEX IF NOT EXISTS idx_alerts_part_updated_at ON ms_alert.alerts_partitioned (updated_at);
CREATE INDEX IF NOT EXISTS idx_alerts_part_composite ON ms_alert.alerts_partitioned (customer_document, status, created_at);

-- Índices compostos para cache optimization
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_alerts_customer_status_created 
ON ms_alert.alerts_partitioned (customer_document, status, created_at DESC);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_alerts_status_updated 
ON ms_alert.alerts_partitioned (status, updated_at DESC);

-- Índices parciais para alertas ativos (otimização de performance)
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_alerts_active_customer 
ON ms_alert.alerts_partitioned (customer_document, created_at DESC) 
WHERE status IN ('CREATED', 'ENRICHING');

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_alerts_completed_customer 
ON ms_alert.alerts_partitioned (customer_document, updated_at DESC) 
WHERE status = 'COMPLETED';

-- 5) Tabela de transações do alerta
CREATE TABLE IF NOT EXISTS ms_alert.alert_tx (
  id            bigserial PRIMARY KEY,
  alert_id      uuid NOT NULL REFERENCES ms_alert.alerts_partitioned(id) ON DELETE CASCADE,
  tx_id         text NOT NULL,
  tx_time       timestamptz NOT NULL,
  amount        numeric(18,2) NOT NULL,
  currency      char(3) NOT NULL,
  direction     text NOT NULL,             -- IN|OUT
  counterparty  jsonb NOT NULL,
  channel       text,
  meta          jsonb NOT NULL DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS ix_alert_tx_alert_time
  ON ms_alert.alert_tx (alert_id, tx_time DESC);

-- 6) Entidades vinculadas ao alerta
CREATE TABLE IF NOT EXISTS ms_alert.alert_entities (
  id            bigserial PRIMARY KEY,
  alert_id      uuid NOT NULL REFERENCES ms_alert.alerts_partitioned(id) ON DELETE CASCADE,
  entity_type   text NOT NULL,             -- DEVICE|ADDR|DOC|ACCOUNT|IP...
  entity_key    text NOT NULL,
  details       jsonb NOT NULL DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS ix_alert_entities_alert
  ON ms_alert.alert_entities (alert_id, entity_type);

-- 7) Features do alerta
CREATE TABLE IF NOT EXISTS ms_alert.alert_features (
  id            bigserial PRIMARY KEY,
  alert_id      uuid NOT NULL REFERENCES ms_alert.alerts_partitioned(id) ON DELETE CASCADE,
  name          text NOT NULL,
  value_num     numeric(20,6),
  value_text    text,
  value_json    jsonb
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_alert_features_alert_name
  ON ms_alert.alert_features (alert_id, name);

-- 8) Artefatos/vínculos S3
CREATE TABLE IF NOT EXISTS ms_alert.alert_artifacts (
  id              bigserial PRIMARY KEY,
  alert_id        uuid NOT NULL REFERENCES ms_alert.alerts_partitioned(id) ON DELETE CASCADE,
  artifact_type   text NOT NULL,        -- ENRICH_PACKAGE|SCREENSHOT|DOC
  s3_uri          text NOT NULL,
  checksum_sha256 text,
  created_at      timestamptz NOT NULL DEFAULT now()
);

-- 9) Função + trigger de updated_at (qualificadas)
CREATE OR REPLACE FUNCTION ms_alert.set_updated_at()
RETURNS trigger AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trig_alerts_updated_at ON ms_alert.alerts_partitioned;

CREATE TRIGGER trig_alerts_updated_at
BEFORE UPDATE ON ms_alert.alerts_partitioned
FOR EACH ROW
EXECUTE FUNCTION ms_alert.set_updated_at();

-- Função para refresh de estatísticas (otimização de performance)
CREATE OR REPLACE FUNCTION ms_alert.refresh_alert_statistics()
RETURNS void AS $
BEGIN
    ANALYZE ms_alert.alerts_partitioned;
    RAISE NOTICE 'Alert statistics refreshed at %', NOW();
END;
$ LANGUAGE plpgsql;

-- Comentários para documentação
COMMENT ON TABLE ms_alert.alerts_partitioned IS 'Main table for storing alert information with partitioning support';
COMMENT ON COLUMN ms_alert.alerts_partitioned.customer_document IS 'Customer document number (CPF/CNPJ)';
COMMENT ON COLUMN ms_alert.alerts_partitioned.scope_start_date IS 'Start date for alert analysis scope';
COMMENT ON COLUMN ms_alert.alerts_partitioned.scope_end_date IS 'End date for alert analysis scope';
COMMENT ON COLUMN ms_alert.alerts_partitioned.status IS 'Current status of the alert processing';
COMMENT ON COLUMN ms_alert.alerts_partitioned.process_id IS 'External process identifier for tracking';
COMMENT ON COLUMN ms_alert.alerts_partitioned.enrichment_data IS 'JSON data with enrichment information';

-- Coleta inicial de estatísticas
ANALYZE ms_alert.alerts_partitioned;
