\connect ms_customer;

-- 1) Schema e search_path desta sessão
CREATE SCHEMA IF NOT EXISTS ms_customer AUTHORIZATION CURRENT_USER;
SET search_path TO ms_customer, public;

-- 2) Extensões necessárias neste DB
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 3) Tabela customers no schema ms_customer
CREATE TABLE IF NOT EXISTS ms_customer.customers (
  id              uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  customer_type   text NOT NULL DEFAULT 'PERSON',  -- PERSON|COMPANY
  name            text NOT NULL,
  username        text,
  document        text NOT NULL,
  birth_date      date,
  registered_at   timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  updated_by      text NOT NULL DEFAULT 'system',
  status          text NOT NULL DEFAULT 'ACTIVE',  -- ACTIVE|BLOCKED|INACTIVE|SUSPENDED|PENDING_VERIFICATION
  income          numeric(24,2) NOT NULL DEFAULT 0,
  is_verified     boolean NOT NULL DEFAULT false,
  email           text,
  phone           text,
  created_at      timestamptz NOT NULL DEFAULT now(),
  company_id      integer
  -- The unique constraint on (document, company_id) is currently disabled to allow multiple customers with the same document per company. Uncomment if uniqueness is required.
  --CONSTRAINT ux_customers_document UNIQUE (document, company_id)
);

-- Índices para performance da tabela customers
CREATE INDEX IF NOT EXISTS idx_customers_document ON ms_customer.customers (document);
CREATE INDEX IF NOT EXISTS idx_customers_status ON ms_customer.customers (status);
CREATE INDEX IF NOT EXISTS idx_customers_name ON ms_customer.customers (name);
CREATE INDEX IF NOT EXISTS idx_customers_email ON ms_customer.customers (email);
CREATE INDEX IF NOT EXISTS idx_customers_created_at ON ms_customer.customers (created_at);
CREATE INDEX IF NOT EXISTS idx_customers_status_created ON ms_customer.customers (status, created_at);
CREATE INDEX IF NOT EXISTS idx_customers_customer_type ON ms_customer.customers (customer_type);
CREATE INDEX IF NOT EXISTS idx_customers_is_verified ON ms_customer.customers (is_verified);
CREATE INDEX IF NOT EXISTS idx_customers_company_id ON ms_customer.customers (company_id);

CREATE TABLE IF NOT EXISTS ms_customer.addresses (
  id              uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  customer_id     uuid NOT NULL REFERENCES ms_customer.customers(id) ON DELETE CASCADE,
  document        text NOT NULL,
  address_type    text NOT NULL,
  street          text NOT NULL,
  number          text,
  complement      text,
  neighborhood    text,
  city            text NOT NULL,
  state           text NOT NULL,
  zip_code        text NOT NULL,
  country         text NOT NULL DEFAULT 'BR',
  is_active       boolean NOT NULL DEFAULT true,
  is_primary      boolean NOT NULL DEFAULT false,
  is_verified     boolean NOT NULL DEFAULT false,
  source_system   text,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  company_id      integer
);

-- Índices para performance da tabela addresses
CREATE INDEX IF NOT EXISTS idx_addresses_customer_id ON ms_customer.addresses (customer_id);
CREATE INDEX IF NOT EXISTS idx_addresses_document ON ms_customer.addresses (document);
CREATE INDEX IF NOT EXISTS idx_addresses_is_primary ON ms_customer.addresses (is_primary);
CREATE INDEX IF NOT EXISTS idx_addresses_is_active ON ms_customer.addresses (is_active);
CREATE INDEX IF NOT EXISTS idx_addresses_zip_code ON ms_customer.addresses (zip_code);
CREATE INDEX IF NOT EXISTS idx_addresses_city_state ON ms_customer.addresses (city, state);

CREATE TABLE IF NOT EXISTS ms_customer.contacts (
  id              uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  customer_id     uuid NOT NULL REFERENCES ms_customer.customers(id) ON DELETE CASCADE,
  document        text NOT NULL,
  contact_value   text NOT NULL,
  contact_type    text NOT NULL CHECK (contact_type IN ('EMAIL', 'PHONE', 'MOBILE', 'WHATSAPP')),
  is_active       boolean NOT NULL DEFAULT true,
  is_primary      boolean NOT NULL DEFAULT false,
  is_verified     boolean NOT NULL DEFAULT false,
  source_system   text,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  updated_by      text NOT NULL DEFAULT 'system',
  company_id      integer
);

-- Índices para performance da tabela contacts
CREATE INDEX IF NOT EXISTS idx_contacts_customer_id ON ms_customer.contacts (customer_id);
CREATE INDEX IF NOT EXISTS idx_contacts_document ON ms_customer.contacts (document);
CREATE INDEX IF NOT EXISTS idx_contacts_contact_type ON ms_customer.contacts (contact_type);
CREATE INDEX IF NOT EXISTS idx_contacts_is_primary ON ms_customer.contacts (is_primary);
CREATE INDEX IF NOT EXISTS idx_contacts_is_active ON ms_customer.contacts (is_active);
CREATE INDEX IF NOT EXISTS idx_contacts_contact_value ON ms_customer.contacts (contact_value);

CREATE TABLE IF NOT EXISTS ms_customer.amlrisk (
  id                     uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  customer_id            uuid NOT NULL REFERENCES ms_customer.customers(id) ON DELETE CASCADE,
  document               text NOT NULL,
  score_cadastro         DECIMAL(5,2) NOT NULL DEFAULT 0 CHECK (score_cadastro >= 0 AND score_cadastro <= 100),
  score_produto          DECIMAL(5,2) NOT NULL DEFAULT 0 CHECK (score_produto >= 0 AND score_produto <= 100),
  score_capacidade_fin   DECIMAL(5,2) NOT NULL DEFAULT 0 CHECK (score_capacidade_fin >= 0 AND score_capacidade_fin <= 100),
  score_total            DECIMAL(5,2) NOT NULL DEFAULT 0 CHECK (score_total >= 0 AND score_total <= 100),
  risk_level             text NOT NULL DEFAULT 'LOW' CHECK (risk_level IN ('LOW', 'MEDIUM', 'HIGH')),
  assessment_model       text NOT NULL, -- modelo que fez o cálculo (ex: 'EAGLE_RISK_V1')
  input_snapshot         JSONB NOT NULL, -- parâmetros usados (renda, produto, histórico etc.)
  calculation_notes      text,  -- observações explicativas (ex: "sem histórico de crédito")
  created_at             timestamptz NOT NULL DEFAULT now(),
  updated_at             timestamptz NOT NULL DEFAULT now(),
  company_id             integer
);

-- Índices para performance da tabela amlrisk
CREATE INDEX IF NOT EXISTS idx_amlrisk_customer_id ON ms_customer.amlrisk (customer_id);
CREATE INDEX IF NOT EXISTS idx_amlrisk_document ON ms_customer.amlrisk (document);
CREATE INDEX IF NOT EXISTS idx_amlrisk_risk_level ON ms_customer.amlrisk (risk_level);
CREATE INDEX IF NOT EXISTS idx_amlrisk_score_total ON ms_customer.amlrisk (score_total);
CREATE INDEX IF NOT EXISTS idx_amlrisk_assessment_model ON ms_customer.amlrisk (assessment_model);
CREATE INDEX IF NOT EXISTS idx_amlrisk_created_at ON ms_customer.amlrisk (created_at);

CREATE TABLE IF NOT EXISTS ms_customer.relationships (
  id                    UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  customer_id           UUID NOT NULL REFERENCES ms_customer.customers(id) ON DELETE CASCADE,
  document              text NOT NULL,
  related_customer_id   UUID NOT NULL REFERENCES ms_customer.customers(id) ON DELETE CASCADE,
  relation_type         VARCHAR(50) NOT NULL CHECK (relation_type IN ('PARTNER', 'REPRESENTATIVE', 'SPOUSE', 'PARENT', 'CHILD', 'SIBLING', 'BUSINESS_PARTNER', 'GUARANTOR')),
  valid_from            timestamptz NOT NULL DEFAULT now(),
  valid_to              timestamptz, -- nullable, used for is_active calculation
  is_active             BOOLEAN NOT NULL DEFAULT true,
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now(),
  updated_by            text NOT NULL DEFAULT 'system'
);

-- Índices para performance da tabela relationships
CREATE INDEX IF NOT EXISTS idx_relationships_customer_id ON ms_customer.relationships (customer_id);
CREATE INDEX IF NOT EXISTS idx_relationships_related_customer_id ON ms_customer.relationships (related_customer_id);
CREATE INDEX IF NOT EXISTS idx_relationships_relation_type ON ms_customer.relationships (relation_type);
CREATE INDEX IF NOT EXISTS idx_relationships_is_active ON ms_customer.relationships (is_active);
CREATE INDEX IF NOT EXISTS idx_relationships_valid_to ON ms_customer.relationships (valid_to);
CREATE UNIQUE INDEX IF NOT EXISTS idx_relationships_unique_active ON ms_customer.relationships (customer_id, related_customer_id, relation_type) WHERE is_active = true;

CREATE TABLE IF NOT EXISTS ms_customer.company (
  id                     uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_name           text NOT NULL,
  group_name             text,
  document               text UNIQUE, -- CNPJ da empresa
  is_active              boolean NOT NULL DEFAULT true,
  created_at             timestamptz NOT NULL DEFAULT now(),
  updated_at             timestamptz NOT NULL DEFAULT now(),
  updated_by             text NOT NULL DEFAULT 'system'
);

-- Índices para performance da tabela company
CREATE INDEX IF NOT EXISTS idx_company_company_name ON ms_customer.company (company_name);
CREATE INDEX IF NOT EXISTS idx_company_group_name ON ms_customer.company (group_name);
CREATE INDEX IF NOT EXISTS idx_company_is_active ON ms_customer.company (is_active);
CREATE INDEX IF NOT EXISTS idx_company_document ON ms_customer.company (document);

-- 4) Função e trigger no schema ms_customer
CREATE OR REPLACE FUNCTION ms_customer.set_updated_at()
RETURNS trigger AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Função para atualizar is_active baseado em valid_to
CREATE OR REPLACE FUNCTION ms_customer.update_relationship_active()
RETURNS trigger AS $$
BEGIN
  NEW.is_active := (NEW.valid_to IS NULL OR NEW.valid_to > now());
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trig_customers_updated_at ON ms_customer.customers;
CREATE TRIGGER trig_customers_updated_at
BEFORE UPDATE ON ms_customer.customers
FOR EACH ROW
EXECUTE FUNCTION ms_customer.set_updated_at();

-- Triggers adicionais para updated_at em todas as tabelas
DROP TRIGGER IF EXISTS trig_addresses_updated_at ON ms_customer.addresses;
CREATE TRIGGER trig_addresses_updated_at
BEFORE UPDATE ON ms_customer.addresses
FOR EACH ROW
EXECUTE FUNCTION ms_customer.set_updated_at();

DROP TRIGGER IF EXISTS trig_contacts_updated_at ON ms_customer.contacts;
CREATE TRIGGER trig_contacts_updated_at
BEFORE UPDATE ON ms_customer.contacts
FOR EACH ROW
EXECUTE FUNCTION ms_customer.set_updated_at();

DROP TRIGGER IF EXISTS trig_amlrisk_updated_at ON ms_customer.amlrisk;
CREATE TRIGGER trig_amlrisk_updated_at
BEFORE UPDATE ON ms_customer.amlrisk
FOR EACH ROW
EXECUTE FUNCTION ms_customer.set_updated_at();

DROP TRIGGER IF EXISTS trig_relationships_updated_at ON ms_customer.relationships;
CREATE TRIGGER trig_relationships_updated_at
BEFORE UPDATE ON ms_customer.relationships
FOR EACH ROW
EXECUTE FUNCTION ms_customer.set_updated_at();

DROP TRIGGER IF EXISTS trig_relationships_active ON ms_customer.relationships;
CREATE TRIGGER trig_relationships_active
BEFORE INSERT OR UPDATE ON ms_customer.relationships
FOR EACH ROW
EXECUTE FUNCTION ms_customer.update_relationship_active();

DROP TRIGGER IF EXISTS trig_company_updated_at ON ms_customer.company;
CREATE TRIGGER trig_company_updated_at
BEFORE UPDATE ON ms_customer.company
FOR EACH ROW
EXECUTE FUNCTION ms_customer.set_updated_at();

-- Comentários nas tabelas para documentação
COMMENT ON TABLE ms_customer.customers IS 'Tabela principal de clientes do sistema Eagle';
COMMENT ON TABLE ms_customer.addresses IS 'Endereços dos clientes';
COMMENT ON TABLE ms_customer.contacts IS 'Contatos dos clientes (email, telefone, etc.)';
COMMENT ON TABLE ms_customer.amlrisk IS 'Avaliação de risco AML (Anti-Money Laundering) dos clientes';
COMMENT ON TABLE ms_customer.relationships IS 'Relacionamentos entre clientes';
COMMENT ON TABLE ms_customer.company IS 'Empresas/grupos empresariais';

-- Log de sucesso
SELECT 'MS-Customer database schema created successfully with optimized indexes and constraints!' as status;