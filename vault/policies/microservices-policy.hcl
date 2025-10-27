# Policy for microservices to access their secrets
path "secret/data/microservices/*" {
  capabilities = ["read"]
}

path "secret/metadata/microservices/*" {
  capabilities = ["list", "read"]
}

# Database dynamic secrets
path "database/creds/eagle-db-role" {
  capabilities = ["read"]
}

path "database/creds/eagle-readonly-role" {
  capabilities = ["read"]
}

# External API secrets
path "secret/data/external-apis/*" {
  capabilities = ["read"]
}

# JWT signing keys
path "secret/data/jwt/*" {
  capabilities = ["read"]
}

# SQS credentials
path "secret/data/aws/*" {
  capabilities = ["read"]
}

# Redis credentials
path "secret/data/redis/*" {
  capabilities = ["read"]
}