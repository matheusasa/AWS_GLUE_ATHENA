# Módulo 09 — Governança, Segurança e Boas Práticas

## Objetivos

Transformar um data lake funcional num data lake **governado, seguro e econômico**: controle de acesso com **Lake Formation**, criptografia, qualidade de dados, tagging, observabilidade e operação no dia a dia.

---

## 1. Por que governança importa

Sem governança, um data lake cresce e vira **data swamp**: ninguém sabe quem pode acessar o quê, não há auditoria, dados sensíveis ficam expostos, custos explodem. Governança é o que torna o lake **confiável e sustentável** para a empresa inteira — não só para engenharia.

Os três pilares: **Segurança** (quem acessa), **Qualidade** (os dados estão certos), **Custo** (estamos gastando bem).

---

## 2. AWS Lake Formation — controle fino de acesso

O Lake Formation se sobrepõe ao S3 + Glue Data Catalog e centraliza quem pode acessar **quais tabelas, colunas e linhas**.

### O que ele resolve que IAM puro não resolve bem

- **Fine-grained access control (FGAC):** "O analista da região SP vê só vendas de SP" (controle por **linha**) e "não vê a coluna `cpf`" (controle por **coluna**).
- **Catálogo central** de permissões, em vez de políticas S3 espalhadas.
- **Ingestão via blueprints** e **tagging LF-Tags** (etiquetas que propagam permissões).

### Padrão com LF-Tags

Você "etiqueta" tabelas/colunas (ex.: `categoria=financeiro`, `sensibilidade=pii`) e depois concede permissão por etiqueta. Mudou a tag → permissão se atualiza em cascata. Muito mais escalável queGrant por tabela.

### Provisionando com Terraform (resumo)

O módulo `glue_catalog_database` do projeto cria o banco; permissões LF podem ser adicionadas:

```hcl
resource "aws_lakeformation_lf_tag" "sensibilidade" {
  key    = "sensibilidade"
  values = ["publico", "interno", "pii"]
}

resource "aws_lakeformation_permissions" "analista_bi" {
  principal   = "arn:aws:iam::111122223333:role/analista-bi"
  permissions = ["DESCRIBE", "SELECT"]

  table_with_columns {
    database_name = aws_glue_catalog_database.this.name
    name          = "vendas_ouro"
    # column_wildcard {} ou colunas específicas
  }
}
```

> **Atenção:** ao ativar Lake Formation sobre um banco existente, ele "toma" o controle. Use `aws_lakeformation_resource` para registrar o bucket S3 e `aws_lakeformation_data_lake_settings` para definir admins. Teste primeiro em dev.

---

## 3. Segurança de dados

- **Criptografia em repouso:** S3 SSE-S3 (AES256) ou SSE-KMS (chave sua, melhor auditoria). Glue/Redshift/Athena também.
- **Criptografia em trânsito:** TLS (padrão na AWS).
- **PII:** classifique e restrinja (Macie descobre PII no S3; Lake Formation mascara/mascara colunas).
- **Segredos:** **nunca** em código/variáveis. Use **Secrets Manager** ou **SSM Parameter Store**; jobs Glue leem via `boto3` ou conector JDBC.
- **Network:** jobs Glue podem rodar em **VPC** (`connections`) para acessar fontes on-prem/privadas.
- **Least privilege:** a role do Glue deve ter o mínimo de S3/IAM/CloudWatch necessário — não a `AWSGlueServiceRole` full.

### Mascaramento de PII (exemplo)

```python
from pyspark.sql.functions import regexp_replace, sha2, col

df = df.withColumn("cpf", regexp_replace(col("cpf"), r".", "*"))        # mascara
df = df.withColumn("email_hash", sha2(col("email"), 256))               # anonimiza
```

---

## 4. Qualidade de dados

### Regras no Glue Data Quality (declarativo)

```yaml
# Data Quality ruleset (exemplo)
Rules = [
  ColumnValues "id_venda" >= 1,
  ColumnLength "cpf" == 11,
  ColumnValues "valor_unit" > 0,
  IsUnique "id_venda",
  Completeness "data_venda" > 0.99,
]
```

Aplique após a Prata; falhas podem bloquear o Ouro (regra `MustClench`) ou só alertar.

### Coluna de validação no código (básico e eficaz)

```python
df = df.withColumn("is_valid",
    (col("valor_total") > 0) &
    (col("id_cliente").isNotNull()) &
    (col("data_venda").isNotNull()))
```

### DataContracts

Defina um **contrato de schema** por camada/tabela (tipos, nulidade, chaves únicas, ranges). Quebrou o contrato na origem? O job falha cedo e avisa, em vez de corromper a Prata.

---

## 5. Tagging e controle de custo

Tags não são cosméticas — são a base de **Cost Explorer**, **showback/chargeback** e **alertas de orçamento**.

```hcl
# No provider default_tags (já vimos) + tags por recurso:
tags = {
  Projeto    = "datalake"
  Ambiente   = "dev"
  Camada     = "prata"
  Dono       = "eng-dados"
  CentroCusto = "CC-1001"
}
```

Ative **AWS Cost Anomaly Detection** e crie **orçamentos** por tag/projeto. No data lake, os grandes vilões de custo costumam ser: **Athena mal particionado** (lê TB a toa), **Glue DPUs em excesso**, **S3 sem lifecycle** (versões antigas acumulando).

### Lifecycle do S3 (apague o que não serve)

```hcl
resource "aws_s3_bucket_lifecycle_configuration" "lake" {
  bucket = aws_s3_bucket.dados.id
  rule {
    id     = "transicao-glacier"
    status = "Enabled"
    filter { prefix = "bronze/" }
    transition { days = 90  storage_class = "STANDARD_IA" }
    transition { days = 365 storage_class = "GLACIER" }
    expiration { days = 2555 }   # 7 anos
  }
}
```

---

## 6. Observabilidade e operação

- **CloudWatch Logs/Metrics:** logs dos jobs, DPUs, erros.
- **Glue Job Run Profile:** perfil por estágio Spark.
- **Alertas:** job falhou → SNS/Slack (CloudWatch Alarm + Lambda/SNS).
- **Catálogo de dados acessível:** documente tabelas no Catálogo (descrições de colunas) e/ou no **AWS Glue Data Catalog + Amazon DataZone**.
- **Linha de dados (lineage):** rastreie origem → bronze → prata → ouro (OpenLineage / DataZone) para auditoria e impacto ("se mudar a Prata, quais Ouros quebram?").

---

## 7. CI/CD para dados (DataOps)

- Infra (Terraform) versionada com pipeline (Módulo 08).
- **Jobs Glue como código:** scripts `.py` no Git, empacotados (zip) e o job atualizado via Terraform (`aws_glue_job`). Mudou o código → `terraform apply` recria/atualiza.
- **Migração de schema** controlada (Iceberg simplifica).
- **Ambientes:** dev (dados sintéticos) → prod. Nunca teste em prod.

---

## 8. Checklist de governança

- [ ] Buckets criptografados, acesso público bloqueado, versionamento on.
- [ ] Lake Formation registrado; permissões por LF-Tag.
- [ ] PII identificada, mascarada/anonimizada onde preciso.
- [ ] Roles least-privilege; segredos no Secrets Manager.
- [ ] Regras de Data Quality ativas na Prata/Ouro.
- [ ] Tags em todos os recursos; Cost Explorer + orçamento.
- [ ] Lifecycle do S3 configurado.
- [ ] Alertas de falha de job; lineage documentada.
- [ ] CI/CD para Terraform + jobs Glue.
- [ ] DR: estado Terraform no S3 versionado; dados críticos replicados.

---

## Exercícios do módulo

**Ex. 1 — LF-Tag:** Provisione uma LF-Tag `sensibilidade` e marque a tabela `vendas_prata` como `interno`. Conceda `SELECT` a um usuário só nas tabelas `interno`.

**Ex. 2 — Mascaramento:** No `silver_transform.py`, mascare a coluna `cpf` (se existir nos dados) antes de gravar a Prata.

**Ex. 3 — Data Quality:** Crie um ruleset mínimo (unicidade de `id_venda`, `valor > 0`) e aplique sobre a Prata. Force um dado inválido e observe o resultado.

**Ex. 4 — Lifecycle:** Adicione uma regra de lifecycle no bucket Bronze: `STANDARD_IA` após 90 dias, `GLACIER` após 365.

**Ex. 5 — Orçamento:** No Cost Explorer, filtre pela tag `Projeto=datalake`. Crie um orçamento mensal com alerta em 80%.

**Ex. 6 — Pergunta:** Por que controlar acesso por **linha** (ex.: só vendas da própria região) é difícil só com IAM/S3, e como o Lake Formation ajuda? ¹

¹ *Porque IAM/S3 controlam acesso a **buckets/objetos/inteiriços**, não ao **conteúdo** dentro dos arquivos. Controle por linha exigiria particionar/objetos por região (impraticável e inflexível). O Lake Formation injeta predicados automaticamente (ex.: adiciona `WHERE regiao='SP'` à consulta do usuário), aplicando a regra de linha de forma transparente, sem expor os demais dados.*
