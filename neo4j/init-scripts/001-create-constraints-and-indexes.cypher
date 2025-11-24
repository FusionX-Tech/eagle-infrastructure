// Neo4j Initialization Script
// Creates constraints and indexes for Eagle Graph Analytics

// ============================================
// CONSTRAINTS (Unique IDs)
// ============================================

// Customer constraints
CREATE CONSTRAINT customer_id_unique IF NOT EXISTS
FOR (c:Customer) REQUIRE c.id IS UNIQUE;

CREATE CONSTRAINT customer_document_unique IF NOT EXISTS
FOR (c:Customer) REQUIRE c.document IS UNIQUE;

// Transaction constraints
CREATE CONSTRAINT transaction_id_unique IF NOT EXISTS
FOR (t:Transaction) REQUIRE t.id IS UNIQUE;

// Alert constraints
CREATE CONSTRAINT alert_id_unique IF NOT EXISTS
FOR (a:Alert) REQUIRE a.id IS UNIQUE;

// Rule constraints
CREATE CONSTRAINT rule_id_unique IF NOT EXISTS
FOR (r:Rule) REQUIRE r.id IS UNIQUE;

// Address constraints
CREATE CONSTRAINT address_id_unique IF NOT EXISTS
FOR (a:Address) REQUIRE a.id IS UNIQUE;

// Contact constraints
CREATE CONSTRAINT contact_id_unique IF NOT EXISTS
FOR (c:Contact) REQUIRE c.id IS UNIQUE;

// Person constraints
CREATE CONSTRAINT person_document_unique IF NOT EXISTS
FOR (p:Person) REQUIRE p.document IS UNIQUE;

// Document constraints
CREATE CONSTRAINT document_value_unique IF NOT EXISTS
FOR (d:Document) REQUIRE d.value IS UNIQUE;

// ============================================
// INDEXES (Performance)
// ============================================

// Customer indexes
CREATE INDEX customer_name IF NOT EXISTS
FOR (c:Customer) ON (c.name);

CREATE INDEX customer_status IF NOT EXISTS
FOR (c:Customer) ON (c.status);

CREATE INDEX customer_type IF NOT EXISTS
FOR (c:Customer) ON (c.customerType);

CREATE INDEX customer_risk_score IF NOT EXISTS
FOR (c:Customer) ON (c.riskScore);

CREATE INDEX customer_registered_at IF NOT EXISTS
FOR (c:Customer) ON (c.registeredAt);

// Transaction indexes
CREATE INDEX transaction_amount IF NOT EXISTS
FOR (t:Transaction) ON (t.amount);

CREATE INDEX transaction_timestamp IF NOT EXISTS
FOR (t:Transaction) ON (t.timestamp);

CREATE INDEX transaction_type IF NOT EXISTS
FOR (t:Transaction) ON (t.transactionType);

CREATE INDEX transaction_status IF NOT EXISTS
FOR (t:Transaction) ON (t.status);

// Alert indexes
CREATE INDEX alert_type IF NOT EXISTS
FOR (a:Alert) ON (a.alertType);

CREATE INDEX alert_status IF NOT EXISTS
FOR (a:Alert) ON (a.status);

CREATE INDEX alert_severity IF NOT EXISTS
FOR (a:Alert) ON (a.severity);

CREATE INDEX alert_created_at IF NOT EXISTS
FOR (a:Alert) ON (a.createdAt);

// Rule indexes
CREATE INDEX rule_type IF NOT EXISTS
FOR (r:Rule) ON (r.ruleType);

CREATE INDEX rule_severity IF NOT EXISTS
FOR (r:Rule) ON (r.severity);

CREATE INDEX rule_active IF NOT EXISTS
FOR (r:Rule) ON (r.isActive);

// ============================================
// RELATIONSHIP INDEXES
// ============================================

// TRANSFERIU relationship indexes
CREATE INDEX transferiu_timestamp IF NOT EXISTS
FOR ()-[t:TRANSFERIU]-() ON (t.timestamp);

CREATE INDEX transferiu_amount IF NOT EXISTS
FOR ()-[t:TRANSFERIU]-() ON (t.amount);

// VIOLOU relationship indexes
CREATE INDEX violou_timestamp IF NOT EXISTS
FOR ()-[v:VIOLOU]-() ON (v.violationTimestamp);

CREATE INDEX violou_severity IF NOT EXISTS
FOR ()-[v:VIOLOU]-() ON (v.severity);

// SOCIO_DE relationship indexes
CREATE INDEX socio_ownership IF NOT EXISTS
FOR ()-[s:SOCIO_DE]-() ON (s.ownershipPercentage);

// SHAREHOLDER_OF relationship indexes
CREATE INDEX shareholder_percentage IF NOT EXISTS
FOR ()-[s:SHAREHOLDER_OF]-() ON (s.percentage);

// Address indexes
CREATE INDEX address_city IF NOT EXISTS
FOR (a:Address) ON (a.city);

CREATE INDEX address_state IF NOT EXISTS
FOR (a:Address) ON (a.state);

CREATE INDEX address_type IF NOT EXISTS
FOR (a:Address) ON (a.addressType);

CREATE INDEX address_is_primary IF NOT EXISTS
FOR (a:Address) ON (a.isPrimary);

// Contact indexes
CREATE INDEX contact_type IF NOT EXISTS
FOR (c:Contact) ON (c.contactType);

CREATE INDEX contact_is_primary IF NOT EXISTS
FOR (c:Contact) ON (c.isPrimary);

// Person indexes
CREATE INDEX person_name IF NOT EXISTS
FOR (p:Person) ON (p.name);

CREATE INDEX person_document IF NOT EXISTS
FOR (p:Person) ON (p.document);

// ============================================
// FULL-TEXT SEARCH INDEXES
// ============================================

// Customer full-text search
CREATE FULLTEXT INDEX customer_fulltext IF NOT EXISTS
FOR (c:Customer) ON EACH [c.name, c.document];

// Alert full-text search
CREATE FULLTEXT INDEX alert_fulltext IF NOT EXISTS
FOR (a:Alert) ON EACH [a.description, a.alertType];

// Rule full-text search
CREATE FULLTEXT INDEX rule_fulltext IF NOT EXISTS
FOR (r:Rule) ON EACH [r.name, c.description];
