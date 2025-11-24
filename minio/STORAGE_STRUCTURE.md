# Estrutura de Armazenamento MinIO - Eagle

## 📦 Buckets

### 1. eagle-attachments
Armazena todos os anexos relacionados a alertas.

### 2. eagle-reports
Armazena relatórios gerados (COAF, analytics, exports).

### 3. eagle-alerts
Armazena metadados e snapshots de alertas.

---

## 📁 Estrutura Detalhada

### eagle-attachments/

```
eagle-attachments/
│
├── alerts/
│   ├── A1B2C3D4E5F6G7H8/                    # Alert ID (Base32)
│   │   ├── 550e8400-e29b-41d4-a716-446655440000.pdf
│   │   │   └─ Metadata: source=system, source-type=alert, category=evidence
│   │   │      (Comprovante de transação anexado pelo sistema)
│   │   │
│   │   ├── 660e8400-e29b-41d4-a716-446655440001.png
│   │   │   └─ Metadata: source=system, source-type=alert, category=document
│   │   │      (Documento de identidade anexado pelo sistema)
│   │   │
│   │   ├── 770e8400-e29b-41d4-a716-446655440002.pdf
│   │   │   └─ Metadata: source=analyst, source-type=opinion, category=analysis
│   │   │      opinion-id=880e8400-e29b-41d4-a716-446655440003
│   │   │      (Relatório de análise criado pelo analista)
│   │   │
│   │   └── 990e8400-e29b-41d4-a716-446655440004.xlsx
│   │       └─ Metadata: source=analyst, source-type=opinion, category=analysis
│   │          opinion-id=880e8400-e29b-41d4-a716-446655440003
│   │          (Planilha de análise criada pelo analista)
│   │
│   ├── B2C3D4E5F6G7H8I9/                    # Outro Alert
│   │   ├── aa0e8400-e29b-41d4-a716-446655440005.pdf
│   │   └── bb0e8400-e29b-41d4-a716-446655440006.png
│   │
│   └── C3D4E5F6G7H8I9J0/                    # Outro Alert
│       └── cc0e8400-e29b-41d4-a716-446655440007.pdf
│
└── temp/                                     # Uploads temporários
    ├── session-abc123/
    │   ├── file-001.tmp
    │   └── file-002.tmp
    └── session-def456/
        └── file-003.tmp
```

### eagle-reports/

```
eagle-reports/
│
├── coaf/
│   ├── 2025/
│   │   ├── 01/
│   │   │   ├── A1B2C3D4E5F6G7H8-20250115143000.xml
│   │   │   └── B2C3D4E5F6G7H8I9-20250120091500.xml
│   │   ├── 02/
│   │   │   └── C3D4E5F6G7H8I9J0-20250205120000.xml
│   │   └── 11/
│   │       └── D4E5F6G7H8I9J0K1-20251120220000.xml
│   └── 2024/
│       └── 12/
│           └── E5F6G7H8I9J0K1L2-20241215100000.xml
│
├── analytics/
│   └── 2025/
│       └── 11/
│           ├── monthly-summary-20251130.pdf
│           ├── alert-trends-20251120.xlsx
│           └── performance-metrics-20251115.csv
│
└── exports/
    └── 2025/
        └── 11/
            ├── alerts-export-20251120.csv
            └── opinions-export-20251120.json
```

### eagle-alerts/

```
eagle-alerts/
│
├── metadata/
│   ├── A1B2C3D4E5F6G7H8.json               # Metadados do alerta
│   ├── B2C3D4E5F6G7H8I9.json
│   └── C3D4E5F6G7H8I9J0.json
│
└── snapshots/
    ├── A1B2C3D4E5F6G7H8-20251120.json      # Snapshot do alerta
    ├── B2C3D4E5F6G7H8I9-20251119.json
    └── C3D4E5F6G7H8I9J0-20251118.json
```

---

## 🏷️ Metadata Schema

### Anexo de Alerta (Original)

```json
{
  "alert-id": "A1B2C3D4E5F6G7H8",
  "file-name": "comprovante-transferencia.pdf",
  "content-type": "application/pdf",
  "source": "system",
  "source-type": "alert",
  "file-category": "evidence",
  "uploaded-by": "system",
  "uploaded-at": "2025-11-20T21:45:00Z",
  "checksum": "sha256:abc123def456...",
  "size": 245678
}
```

### Anexo de Parecer (Analista)

```json
{
  "alert-id": "A1B2C3D4E5F6G7H8",
  "file-name": "relatorio-analise-detalhada.pdf",
  "content-type": "application/pdf",
  "source": "analyst",
  "source-type": "opinion",
  "opinion-id": "550e8400-e29b-41d4-a716-446655440000",
  "file-category": "analysis",
  "uploaded-by": "analyst-123",
  "uploaded-at": "2025-11-20T22:00:00Z",
  "checksum": "sha256:def456ghi789...",
  "size": 512345
}
```

### Relatório COAF

```json
{
  "alert-id": "A1B2C3D4E5F6G7H8",
  "file-name": "A1B2C3D4E5F6G7H8-20251120220000.xml",
  "content-type": "application/xml",
  "report-type": "coaf",
  "generated-by": "system",
  "generated-at": "2025-11-20T22:00:00Z",
  "protocol-number": "COAF-2025-001234",
  "checksum": "sha256:ghi789jkl012..."
}
```

---

## 🔍 Queries Comuns

### Listar todos os anexos de um alerta

```bash
mc ls myminio/eagle-attachments/alerts/A1B2C3D4E5F6G7H8/
```

### Listar apenas anexos originais (do sistema)

```bash
# Filtrar por metadata source=system
mc find myminio/eagle-attachments/alerts/A1B2C3D4E5F6G7H8/ --metadata "source=system"
```

### Listar apenas anexos de pareceres (do analista)

```bash
# Filtrar por metadata source=analyst
mc find myminio/eagle-attachments/alerts/A1B2C3D4E5F6G7H8/ --metadata "source=analyst"
```

### Listar anexos de um parecer específico

```bash
# Filtrar por opinion-id
mc find myminio/eagle-attachments/alerts/A1B2C3D4E5F6G7H8/ --metadata "opinion-id=550e8400-e29b-41d4-a716-446655440000"
```

### Deletar todos os anexos de um alerta

```bash
mc rm --recursive myminio/eagle-attachments/alerts/A1B2C3D4E5F6G7H8/
```

---

## 📊 Vantagens da Estrutura Simplificada

✅ **Simplicidade**: Tudo relacionado ao alerta em uma única pasta  
✅ **Performance**: Menos navegação de diretórios  
✅ **Flexibilidade**: Metadata permite queries complexas  
✅ **Manutenção**: Fácil deletar/arquivar todos os anexos de um alerta  
✅ **Rastreabilidade**: Metadata indica origem e contexto de cada arquivo  
✅ **Escalabilidade**: Estrutura flat escala melhor que hierarquias profundas  

---

## 🔄 Lifecycle Policies

### Temp Files (7 dias)

```bash
mc ilm add --expiry-days 7 myminio/eagle-attachments/temp/
```

### Old Reports (1 ano)

```bash
mc ilm add --expiry-days 365 myminio/eagle-reports/analytics/
```

### COAF Reports (Permanente)

```bash
# Não aplicar lifecycle - manter permanentemente
```

---

## 🔐 Access Policies

### Service Account (eagle-service)

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::eagle-attachments/*",
        "arn:aws:s3:::eagle-reports/*",
        "arn:aws:s3:::eagle-alerts/*"
      ]
    }
  ]
}
```

### Read-Only Account (eagle-viewer)

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::eagle-attachments/*",
        "arn:aws:s3:::eagle-reports/*"
      ]
    }
  ]
}
```
