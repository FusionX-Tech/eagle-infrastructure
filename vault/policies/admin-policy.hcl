# Admin policy for full access to secrets management
path "*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

# System backend access
path "sys/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

# Auth methods
path "auth/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

# Database secrets engine
path "database/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# KV secrets engine
path "secret/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}