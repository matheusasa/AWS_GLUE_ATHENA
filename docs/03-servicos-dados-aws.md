# Módulo 03 — Serviços de Dados da AWS: Visão Geral

## Objetivos

Entender o **menu** de serviços de dados da AWS, quando usar cada um e como eles se encaixam numa arquitetura. Este módulo é um "mapa"; os próximos aprofundam no **Glue + PySpark**.

---

## 1. Os "5 blocos" de uma plataforma de dados

Toda plataforma de dados faz, no fundo, cinco coisas. A AWS tem serviços para cada uma:

1. **Armazenamento** → onde os dados ficam (S3).
2. **Movimentação / Ingestão** → como entram (Kinesis, DMS, Glue, Kafka/MSK).
3. **Processamento / Transformação** → como viram algo útil (Glue, EMR, Lambda).
4. **Catálogo & Consulta** → como acha e lê (Glue Data Catalog, Athena, Redshift).
5. **Governaça & Segurança** → quem acessa o quê (Lake Formation, IAM, Macie).

E na ponta de consumo: **BI / Analytics** (QuickSight), **ML** (SageMaker).

---

## 2. Armazenamento

### Amazon S3 — o data lake de fato

- Armazenamento de **objetos**, barato, durável (11 noves), praticamente infinito.
- É a **base de tudo**: Glue, Athena, Redshift e EMR leem do S3.
- Organize por **prefixos/camadas** (`s3://bucket/bronze/`, `/prata/`, `/ouro/`).
- Formatos: prefira **Parquet** (colunar, comprimido) ou **Apache Iceberg** para dados analíticos. Evite JSON/CSV para volumes grandes.

> **Por que Parquet?** É colunar e comprimido. Consultas que leem poucas colunas (típico em analytics) pulam blocos inteiros ("predicate pushdown"), reduzindo custo e tempo no S3/Athena/Glue.

---

## 3. Ingestão / Movimentação

| Serviço | Quando usar |
|---|---|
| **AWS DMS** | Migrar bancos relacionais (Oracle, Postgres) para o S3 com mínima reconfiguração |
| **Amazon Kinesis Data Streams/Firehose** | Streaming de alta vazia (logs, eventos, clickstream) |
| **Amazon MSK** | Kafka gerenciado |
| **AWS Glue** | ETL em batch e micro-batch, conectores a fontes JDBC/API |
| **Amazon AppFlow** | SaaS → S3 (Salesforce, SAP) sem código |
| **AWS Lambda** | Ingestão leve/event-driven (a cada upload, processa) |

**Padrão:** Kinesis/Firehose para streaming → S3 (camada Bronze) → Glue processa → camadas Prata/Ouro.

---

## 4. Processamento / Transformação (o coração do curso)

### AWS Glue

Serviço **serverless** de ETL que roda **Apache Spark** (e também ray/Python shell) por baixo dos panos. Você escreve **PySpark** e o Glue gerencia o cluster. É o foco dos Módulos 04–06.

- **Glue Studio:** interface visual + editor de scripts.
- **Glue Jobs:** o job de ETL propriamente dito (PySpark).
- **Glue Crawlers:** varrem o S3 e **descobrem o schema**, populando o Catálogo.
- **Glue DataBrew:** transformação visual sem código (perfilamento, limpeza).
- **Glue Data Quality:** regras de qualidade declarativas.

### Amazon EMR

Cluster **Spark/Hadoop/Presto gerenciado por você** (você escolhe instâncias). Mais controle, mais barato para workloads contínuos/pesados, mas mais operação. Use quando o Glue não der (libs customizadas pesadas, tuning fino, long-running).

### AWS Lambda

Transformações **leves e event-driven** (arquivo cai no S3 → Lambda transforma). Não é para big data (limite de 15 min e memória), mas é ótimo para orquestração de "cola".

---

## 5. Catálogo & Consulta

### Glue Data Catalog

O **índice central**: mapeia "tabela" → caminho no S3 + schema (colunas, tipos, partições). Athena, Redshift, EMR e o próprio Glue consultam o Catálogo. Sem ele, toda ferramenta precisaria adivinhar o schema.

- Tabelas são **metadados**: a "tabela" `vendas_bronze` é apenas um ponteiro para `s3://bucket/bronze/vendas/` + a definição das colunas.
- **Crawlers** descobrem o schema automaticamente.

### Amazon Athena

**Consulta serverless com SQL** diretamente no S3, usando o Catálogo. Sem servidor para gerenciar — paga por TB lido. Ideal para análises ad-hoc e para validar o resultado dos seus jobs Glue.

```sql
SELECT cliente, SUM(valor) AS total
FROM vendas_prata
WHERE dt = '2026-06-01'
GROUP BY cliente
ORDER BY total DESC;
```

### Amazon Redshift

**Data Warehouse** para SQL de alto volume e BI. Pode ler do S3 (Redshift Spectrum) e do Catálogo. Use quando você precisa de um warehouse OLAP consolidado com alto desempenho e concorrência.

---

## 6. Governança & Segurança

### AWS Lake Formation

Camada de **governaça** sobre o S3 + Glue Data Catalog. Centraliza controle de acesso **a nível de tabela/coluna/linha** (fine-grained), auditoria, e ingestão via "blueprints". É o que transforma "um monte de arquivos no S3" num data lake **governável**.

### Outros
- **AWS IAM:** quem/qual serviço pode fazer o quê.
- **AWS KMS:** chaves de criptografia.
- **Amazon Macie:** detecta dados sensíveis (PII) no S3.
- **AWS CloudTrail:** auditoria de API.

---

## 7. Consumo

- **Amazon QuickSight:** BI serverless, conecta em Athena/Redshift/S3.
- **Amazon SageMaker:** ML (treino em dados do data lake).
- **Aplicações próprias:** via Athena (JDBC) ou APIs.

---

## 8. Arquitetura-referência (visão de 30.000 pés)

```
Fontes (RDBMS, APIs, logs, streaming)
        │
        ▼
 [Ingestão]  DMS / Kinesis Firehose / Glue connectors
        │
        ▼
   ┌───────────  S3 (Data Lake)  ───────────┐
   │  bronze/  →  prata/  →  ouro/          │   ← arquitetura medalhão
   └─────────────────────────────────────────┘
        ▲             ▲              ▲
        │             │              │
 [Glue Crawlers]  [Glue Jobs]   [Glue Data Quality]
        └─────────────┴──────────────┘
                      │
              Glue Data Catalog
                      │
        ┌─────────────┼─────────────┐
        ▼             ▼             ▼
     Athena      Redshift        QuickSight / SageMaker

  [Lake Formation governa o acesso de ponta a ponta]
  [Tudo provisionado por Terraform, replicado dev/prod]
```

**Fluxo típico do curso:** dados crus chegam ao **bronze** (sem transformação), jobs PySpark limpam/enriquecem e levam ao **prata**, agregações de negócio geram o **ouro**, e Athena/QuickSight consomem.

---

## Exercícios do módulo

**Ex. 1 — Mapa mental:** Desenhe (no papel) onde entram S3, Glue, Athena, Lake Formation e Redshift numa empresa de e-commerce. Quem ingesta, quem transforma, quem consulta?

**Ex. 2 — Escolha o serviço:** Para cada cenário, indique o serviço: (a) migrar um Postgres para o S3; (b) processar 2 TB de logs por dia em PySpark sem gerenciar cluster; (c) consulta SQL ad-hoc no S3; (d) streaming de clicks em tempo real. ¹

**Ex. 3 — Athena na prática:** (Após o Módulo 02) suba um bucket, suba um CSV e, no console Athena, faça um `SELECT`. Veja como o Athena **cobra por TB lido** — por isso Parquet + particionamento importam.

**Ex. 4 — Pergunta:** Por que dizemos que o Glue Data Catalog contém "metadados" e não os dados em si? ²

¹ *(a) DMS; (b) Glue; (c) Athena; (d) Kinesis (Streams/Firehose).*
² *Porque uma "tabela" no Catálogo é apenas a definição (colunas, tipos, localização no S3). Os dados ficam nos arquivos do S3; o Catálogo só diz onde estão e qual o formato.*
