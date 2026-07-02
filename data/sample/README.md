# data/sample — Dados de exemplo para os laboratórios

Dados sintéticos e fictícios (nomes/categorias não reais) para testar os jobs
do Glue sem dados sensíveis.

## Arquivos

### `vendas.csv`
Fato de vendas. Use para o Lab 1 (Bronze) em diante.

| Coluna | Tipo esperado | Descrição |
|---|---|---|
| `id_venda` | int | Chave da venda (usada para dedup na Prata) |
| `id_cliente` | int | FK para `clientes` |
| `id_produto` | int | FK para `produtos` |
| `quantidade` | int | Quantidade vendida |
| `valor_unit` | double | Valor unitário |
| `data_venda` | timestamp | `yyyy-MM-dd HH:mm:ss` |
| `canal` | string | online, loja, app |

### `clientes.csv`
Dimensão de clientes: `id_cliente, nome, regiao`. Regiões: Sudeste, Sul,
Nordeste, Norte, Centro-Oeste.

### `produtos.csv`
Dimensão de produtos: `id_produto, categoria, marca`. Categorias: Eletronicos,
Vestuario, Casa, Livros.

### `vendas_dia2.csv`
Vendas de um "segundo dia" (Lab 4 — incremental com bookmark). Suba em
`bronze/landing/vendas/dt=2026-07-02/` **depois** da primeira carga para
ver o job processar só o novo.

## Gerando volume maior com `generate_data.py`

Os CSVs acima são exemplos mínimos (prontos para uso). Para volumes maiores
e realistas, use o gerador com **Faker** (locale `pt_BR`):

```bash
pip install -r requirements.txt        # instala o faker
python generate_data.py --clientes 200 --produtos 50 --vendas 5000 --outdir .
```

Opções úteis:

- `--seed 42` — reprodutível (mesma seed = mesmos dados).
- `--dirty 0.02` — injeta ~2% de registros sujos (valor negativo, campos
  vazios, duplicidade de `id_venda`) para testar **dedup** e a coluna
  `is_valid` da Prata.
- `--with-pii` — gera também `clientes_pii.csv` (CPF, e-mail, telefone,
  cidade) para o exercício de **mascaramento de PII** (Módulo 09).

O schema gerado é **idêntico** ao esperado pelos jobs Glue.

## Como subir para a Bronze (após `terraform apply`)

```bash
BUCKET=$(terraform -chdir=terraform/envs/dev output -json buckets | jq -r .bronze)
aws s3 cp vendas.csv   s3://$BUCKET/landing/vendas/dt=2026-07-01/
aws s3 cp clientes.csv s3://$BUCKET/landing/clientes/dt=2026-07-01/
aws s3 cp produtos.csv s3://$BUCKET/landing/produtos/dt=2026-07-01/
```

## Ideias para enriquecer os exercícios

- **PII:** adicione uma coluna `cpf` em `clientes.csv` e mascare-a na Prata (Módulo 09).
- **Qualidade:** insira uma linha com `valor_unit` negativo e veja `is_valid=false`.
- **Duplicidade:** rode o job Bronze duas vezes sobre o mesmo arquivo e observe
  a dedup atuando na Prata (mantém o `ingestao_ts` mais recente).
