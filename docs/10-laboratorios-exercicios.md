# Módulo 10 — Laboratórios Práticos e Exercícios

## Objetivos

Colocar tudo junto em uma trilha de **laboratórios progressivos** que constroem, do zero, um Data Lake na **Arquitetura Medalhão** usando Terraform + Glue/PySpark. Cada laboratório tem objetivo, passo a passo e **solução comentada** (nas pastas `terraform/`, `glue-jobs/` e `data/sample/`).

> ⚠️ Lembre: recursos na AWS custam. Use a conta de `dev`, `terraform destroy` ao final, e confira o gasto no **Cost Explorer**.

---

## Roteiro dos laboratórios

| Lab | Foco | Nível |
|---|---|---|
| **Lab 0** | Setup: subir a infra com Terraform | Básico |
| **Lab 1** | Bronze: ingestão cru → S3 | Básico |
| **Lab 2** | Prata: limpeza, joins, dedup | Intermediário |
| **Lab 3** | Ouro: agregação + consulta no Athena | Intermediário |
| **Lab 4** | Incremental com bookmarks | Avançado |
| **Lab 5** | Upsert com Apache Iceberg | Avançado |
| **Capstone** | Pipeline completo orquestrado | Avançado |

---

## Lab 0 — Setup da infraestrutura com Terraform

**Objetivo:** provisionar bucket S3, Catálogo Glue, role IAM, Athena e os jobs — tudo via código.

### Passo a passo

1. Configure credenciais AWS: `aws configure` (região `sa-east-1`).
2. Crie o **bucket de estado** e a tabela de lock uma única vez (ver Módulo 02, seção 4). Use nomes únicos.
3. Edite `terraform/envs/dev/backend.tf` com o nome do seu bucket de estado.
4. Copie `terraform/envs/dev/terraform.tfvars.example` → `terraform.tfvars` e ajuste (`projeto`, `regiao`, sufixo único de bucket).
5. Aplique:

```bash
make tf-init-dev
make tf-plan-dev      # LEIA o plano
make tf-apply-dev
```

6. Suba os dados de exemplo para a Bronze:

```bash
aws s3 cp data/sample/vendas.csv   s3://<seu-bucket>/bronze/landing/vendas/dt=2026-07-01/
aws s3 cp data/sample/clientes.csv s3://<seu-bucket>/bronze/landing/clientes/dt=2026-07-01/
aws s3 cp data/sample/produtos.csv s3://<seu-bucket>/bronze/landing/produtos/dt=2026-07-01/
```

7. Rode o **Crawler** criado pelo Terraform (ou `aws glue start-crawler --name <crawler>`) para popular o Catálogo da Bronze.

**✅ Sucesso:** `aws glue get-tables --database datalake_bronze` lista as tabelas `vendas`, `clientes`, `produtos`.

**Solução de referência:** pasta `terraform/envs/dev/` + módulos em `terraform/modules/`.

---

## Lab 1 — Bronze: ingestão cru para S3

**Objetivo:** escrever um job Glue que lê o CSV cru da landing, adiciona colunas de controle e grava Parquet na Bronze (append-only).

**Passo a passo**

1. Abra `glue-jobs/bronze_ingest.py`. Entenda: lê parâmetros `INPUT_PATH`/`OUTPUT_PATH`/`TABLE`, adiciona `ingestao_ts`, `arquivo_origem`, `batch_id`, e grava Parquet particionado por `dt_ingestao`.
2. Rode o job (criado pelo Terraform no Lab 0) passando os parâmetros:

```text
--TABLE=vendas
--INPUT_PATH=s3://<bucket>/bronze/landing/vendas/
--OUTPUT_PATH=s3://<bucket>/bronze/vendas/
```

3. No Glue Studio → Runs, acompanhe. Em **Athena**, depois de um crawler na Bronze, rode:

```sql
SELECT COUNT(*) FROM vendas_bronze;
SELECT *, arquivo_origem FROM vendas_bronze LIMIT 5;
```

**✅ Sucesso:** a Bronze tem os dados em Parquet, com colunas de controle, **sem** alterar o conteúdo original.

**Erros comuns & correções**

- `Path does not exist` → confira `INPUT_PATH` e o upload.
- Bookmark não avança → adicionou `transformation_ctx` na origem? (Módulo 06, seção 7).
- Small files → use `repartitionByRange` antes do `write`.

---

## Lab 2 — Prata: limpeza, joins e deduplicação

**Objetivo:** transformar Bronze → Prata com tipos corretos, enriquecimento (joins) e `dropDuplicates`.

**Passo a passo**

1. Abra `glue-jobs/silver_transform.py`. Ele: lê as 3 tabelas da Bronze, faz cast de tipos, deduplica por `id_venda`, faz `broadcast join` com clientes e produtos, calcula `valor_total` e grava Parquet particionado por `ano`/`mes`.
2. Rode o job com:

```text
--BRONZE_DB=datalake_bronze
--SILVER_PATH=s3://<bucket>/prata/vendas/
```

3. Crie/rode o crawler para a Prata. Valide no Athena:

```sql
SELECT cliente_regiao, produto_categoria,
       SUM(valor_total) AS receita
FROM vendas_prata
WHERE ano=2026 AND mes=7
GROUP BY 1,2
ORDER BY receita DESC;
```

**✅ Sucesso:** Prata sem duplicidade de `id_venda`, colunas tipadas, `valor_total` calculado.

**Solução comentada** (trecho-chave):

```python
# Dedup mantendo o mais recente por ingestao_ts
w = Window.partitionBy("id_venda").orderBy(col("ingestao_ts").desc())
df = df.withColumn("rn", row_number().over(w)).filter("rn=1").drop("rn")

# Enriquecimento com broadcast (tabelas pequenas)
df = (df.join(broadcast(df_clientes), "id_cliente", "left")
        .join(broadcast(df_produtos), "id_produto", "left"))
```

---

## Lab 3 — Ouro: agregação para consumo

**Objetivo:** gerar o Ouro `vendas_regiao_mes` e consumir no Athena/QuickSight.

**Passo a passo**

1. Abra `glue-jobs/gold_aggregate.py`: lê a Prata, agrega por `cliente_regiao`/`produto_categoria`/`ano`/`mes`, calcula `receita`, `qtd_vendas`, `ticket_medio`, grava Parquet particionado.
2. Rode o job; crie o crawler para o Ouro.
3. No Athena, compare custo entre Prata e Ouro (veja **Bytes scanned**): a mesma pergunta de negócio consome **muito menos** lendo o Ouro.
4. (Opcional) Conecte o QuickSight ao Athena e faça um gráfico de barras de receita por região.

**✅ Sucesso:** consulta de dashboard responde em segundos, lendo poucos MB.

---

## Lab 4 — Carga incremental com bookmarks (avançado)

**Objetivo:** reprocessar só o que é novo.

**Passo a passo**

1. No job da Bronze, habilite bookmark (`--job-bookmark-option=job-bookmark-enable`) e garanta `transformation_ctx` em todas as origens.
2. Suba um **novo** arquivo para a landing:

```bash
aws s3 cp data/sample/vendas_dia2.csv s3://<bucket>/bronze/landing/vendas/dt=2026-07-02/
```

3. Rode o job Bronze de novo. No log, veja que ele processou **só o novo**.
4. Para recomeçar do zero: `aws glue reset-job-bookmark --job-name <job>`.

**✅ Sucesso:** segunda execução lê só `dt=2026-07-02`.

---

## Lab 5 — Upsert com Apache Iceberg (avançado)

**Objetivo:** demonstrar `MERGE` (atualizar vendas sem duplicar).

**Passo a passo**

1. Crie uma tabela Iceberg (configure catalog no Spark — Módulo 06, seção 9).
2. Insira os dados da Prata:

```sql
CREATE TABLE glue_catalog.datalake_prata.vendas_iceberg
USING iceberg PARTITIONED BY (ano, mes)
AS SELECT * FROM vendas_prata;
```

3. Prepare um DataFrame de "correções" (mesmo `id_venda`, valor novo) e faça:

```sql
MERGE INTO glue_catalog.datalake_prata.vendas_iceberg AS t
USING df_correcoes AS s ON t.id_venda = s.id_venda
WHEN MATCHED THEN UPDATE SET *
WHEN NOT MATCHED THEN INSERT *;
```

4. Verifique `SELECT` antes/depois: **atualizou**, não duplicou. Faça `time travel`:

```sql
SELECT * FROM glue_catalog.datalake_prata.vendas_iceberg.snapshots;
SELECT * FROM glue_catalog.datalake_prata.vendas_iceberg VERSION AS OF <snapshot-id>;
```

**✅ Sucesso:** upsert funciona e o histórico é preservado.

---

## Capstone — Pipeline orquestrado de ponta a ponta

**Objósito:** orquestrar Bronze → Prata → Ouro com **AWS Step Functions**.

**Passo a passo (resumo)**

1. Use o padrão **Glue StartJobRun + wait** no Step Functions em cadeia:

```
StartJobRun(bronze) → Wait → Check(bronze) → StartJobRun(silver) → Wait → Check → StartJobRun(gold)
```

2. Em caso de falha, ramifique para um estado de **retry/alerta (SNS)**.
3. Agende diariamente com **EventBridge** (`cron(0 2 * * ? *)`).
4. Provisione o Step Function e o agendamento **no Terraform**.

**Critérios de conclusão**

- Infra 100% em Terraform, replicável dev/prod.
- Jobs Bronze/Prata/Ouro idempotentes e incrementais.
- Qualidade de dados checada; falhas alertam.
- Athena consulta o Ouro rapidamente; QuickSight consome.
- Governança: tags, criptografia, permissões via Lake Formation.

---

## Exercícios extras (sem solução direta — pratique)

1. **PII:** adicione uma coluna `cpf` aos dados de clientes e mascare-a na Prata.
2. **Data Quality:** crie um ruleset que bloqueie a Prata se `valor_total <= 0`.
3. **Skew:** injete um cliente com volume desproporcional e observe o estágio lento; corrija com AQE `skewJoin`.
4. **Lineage:** documente (em markdown) a origem → bronze → prata → ouro de cada coluna do Ouro.
5. **Destruir:** `make tf-destroy-dev` e confirme que o **Cost Explorer** zera o gasto do projeto.

---

## Solução de problemas (FAQ rápido)

| Sintoma | Provável causa | Ação |
|---|---|---|
| Job falha "AccessDenied S3" | Role sem permissão no bucket | Revise IAM/LF na role do Glue |
| Lentidão extrema | Small files / shuffle / sem AQE | `repartition`, AQE, broadcast |
| Duplicidade na Prata | Sem `dropDuplicates` ou reprocessou Bronze sem dedup | Adicione dedup; use Iceberg |
| Athena lê TB | Sem partição / filtro não usa coluna de partição | Particione; filtre por `ano`/`mes` |
| Bookmark não avança | Falta `transformation_ctx` | Adicione ctx único em cada origem |
| `terraform plan` quer recriar tudo | Recurso depende de nome não-determinístico | Use `name_prefix`/`ignore_changes` |

Bons laboratórios! Ao final do capstone, você terá um data lake governado, reproduzível e pronto para produção. 🚀
