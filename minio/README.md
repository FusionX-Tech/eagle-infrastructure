# MinIO Object Storage - Eagle Infrastructure

MinIO é um servidor de armazenamento de objetos compatível com S3, usado para armazenar anexos, relatórios e outros arquivos do sistema Eagle.

## 🚀 Acesso

- **API Endpoint**: http://localhost:9000
- **Console Web**: http://localhost:9001
- **Credenciais Root**: 
  - User: `minioadmin`
  - Password: `minioadmin`

## 📦 Buckets Criados Automaticamente

1. **eagle-alerts**: Armazenamento de dados relacionados a alertas
2. **eagle-attachments**: Anexos de alertas (PDFs, imagens, documentos)
3. **eagle-reports**: Relatórios gerados (COAF, análises, etc.)

## 🔐 Service Account

Para uso pelos microserviços:
- **User**: `eagle-service`
- **Password**: `eagle-service-password`
- **Policy**: `readwrite` (acesso completo aos buckets)

## 🛠️ Comandos Úteis

### Usando MinIO Client (mc)

```bash
# Configurar alias
mc alias set myminio http://localhost:9000 minioadmin minioadmin

# Listar buckets
mc ls myminio

# Listar objetos em um bucket
mc ls myminio/eagle-attachments

# Upload de arquivo
mc cp local-file.pdf myminio/eagle-attachments/

# Download de arquivo
mc cp myminio/eagle-attachments/file.pdf ./

# Remover arquivo
mc rm myminio/eagle-attachments/file.pdf

# Ver estatísticas
mc admin info myminio
```

### Usando AWS CLI (compatível com S3)

```bash
# Configurar credenciais
aws configure set aws_access_key_id minioadmin
aws configure set aws_secret_access_key minioadmin
aws configure set region us-east-1

# Listar buckets
aws --endpoint-url http://localhost:9000 s3 ls

# Upload de arquivo
aws --endpoint-url http://localhost:9000 s3 cp file.pdf s3://eagle-attachments/

# Download de arquivo
aws --endpoint-url http://localhost:9000 s3 cp s3://eagle-attachments/file.pdf ./

# Listar objetos
aws --endpoint-url http://localhost:9000 s3 ls s3://eagle-attachments/
```

## 🔧 Configuração no Código Go

```go
import (
    "github.com/minio/minio-go/v7"
    "github.com/minio/minio-go/v7/pkg/credentials"
)

// Inicializar cliente MinIO
minioClient, err := minio.New("localhost:9000", &minio.Options{
    Creds:  credentials.NewStaticV4("eagle-service", "eagle-service-password", ""),
    Secure: false, // true para HTTPS
})

// Upload de arquivo
_, err = minioClient.FPutObject(context.Background(),
    "eagle-attachments",
    "alert-123/document.pdf",
    "/path/to/local/file.pdf",
    minio.PutObjectOptions{ContentType: "application/pdf"},
)

// Download de arquivo
err = minioClient.FGetObject(context.Background(),
    "eagle-attachments",
    "alert-123/document.pdf",
    "/path/to/save/file.pdf",
    minio.GetObjectOptions{},
)

// Gerar URL pré-assinada (válida por 1 hora)
presignedURL, err := minioClient.PresignedGetObject(context.Background(),
    "eagle-attachments",
    "alert-123/document.pdf",
    time.Hour,
    nil,
)
```

## 📊 Monitoramento

MinIO expõe métricas Prometheus em:
- **Endpoint**: http://localhost:9000/minio/v2/metrics/cluster
- **Tipo**: Prometheus format

Métricas disponíveis:
- Uso de disco
- Número de objetos
- Throughput de rede
- Latência de operações
- Taxa de erros

## 🔒 Segurança

### Produção

Para ambientes de produção, configure:

1. **HTTPS**: Habilite TLS
2. **Credenciais fortes**: Altere usuário/senha padrão
3. **Políticas de acesso**: Configure IAM policies específicas
4. **Encryption at rest**: Habilite criptografia de dados
5. **Backup**: Configure replicação ou backup regular

### Políticas de Bucket

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {"AWS": ["arn:aws:iam::eagle-service"]},
      "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"],
      "Resource": ["arn:aws:s3:::eagle-attachments/*"]
    }
  ]
}
```

## 🐳 Docker Commands

```bash
# Iniciar MinIO
docker-compose --profile infra up -d minio

# Ver logs
docker logs -f fx-minio

# Reiniciar
docker-compose restart minio

# Parar
docker-compose stop minio

# Remover (dados persistem no volume)
docker-compose down minio
```

## 📁 Estrutura de Diretórios

```
eagle-attachments/
├── alerts/
│   └── {alert-id}/                          # Ex: A1B2C3D4E5F6G7H8
│       ├── {file-id}.pdf                    # Anexos originais do alerta
│       ├── {file-id}.png                    # Anexos do parecer do analista
│       └── {file-id}.xlsx                   # Diferenciados por metadata
└── temp/                                    # Uploads temporários (lifecycle: 7 dias)
    └── {upload-session-id}/
        └── {file-id}.tmp

eagle-reports/
├── coaf/
│   └── {year}/{month}/
│       └── {alert-id}-{timestamp}.xml
├── analytics/
│   └── {year}/{month}/
│       └── {report-type}-{timestamp}.pdf
└── exports/

eagle-alerts/
├── metadata/
└── snapshots/
```

### Diferenciação por Metadata

Todos os anexos ficam na mesma pasta `alerts/{alert-id}/`, mas são diferenciados por metadata:

**Anexo Original do Alerta (Sistema):**
```json
{
  "alert-id": "A1B2C3D4E5F6G7H8",
  "file-name": "comprovante.pdf",
  "source": "system",
  "source-type": "alert",
  "file-category": "evidence",
  "uploaded-by": "system",
  "uploaded-at": "2025-11-20T21:45:00Z"
}
```

**Anexo do Parecer (Analista):**
```json
{
  "alert-id": "A1B2C3D4E5F6G7H8",
  "file-name": "relatorio-analise.pdf",
  "source": "analyst",
  "source-type": "opinion",
  "opinion-id": "550e8400-e29b-41d4-a716-446655440000",
  "file-category": "analysis",
  "uploaded-by": "analyst-123",
  "uploaded-at": "2025-11-20T22:00:00Z"
}
```

## 🔄 Lifecycle Policies

Configure políticas de ciclo de vida para gerenciar automaticamente objetos antigos:

```bash
# Exemplo: Deletar objetos temporários após 7 dias
mc ilm add --expiry-days 7 myminio/eagle-attachments/temp/
```

## 🆘 Troubleshooting

### Problema: Container não inicia

```bash
# Verificar logs
docker logs fx-minio

# Verificar permissões do volume
docker volume inspect eagle-infrastructure_minio-data
```

### Problema: Não consegue conectar

```bash
# Verificar se o container está rodando
docker ps | grep minio

# Testar conectividade
curl http://localhost:9000/minio/health/live
```

### Problema: Buckets não foram criados

```bash
# Executar manualmente o init
docker-compose up minio-init
```

## 📚 Referências

- [MinIO Documentation](https://min.io/docs/minio/linux/index.html)
- [MinIO Go SDK](https://min.io/docs/minio/linux/developers/go/minio-go.html)
- [S3 API Compatibility](https://min.io/docs/minio/linux/developers/s3-compatible-api.html)
