# Módulo 11 — Orquestração com AWS Step Functions

> Foco deste módulo: **orquestração**. Como coordenar a execução dos jobs Glue
> (Bronze → Prata → Ouro) com Step Functions. Não trata de transformações
> (esses estão nos Módulos 04–07).

## Objetivos

Entender o que é o **AWS Step Functions**, quando usá-lo para orquestrar ETL,
o padrão de integração `.sync` com o Glue e como provisioná-lo com Terraform.

---

## 1. O que é o Step Functions

O **AWS Step Functions** é um serviço de **orquestração de fluxos (workflows)
serverless**. Você descreve uma máquina de estados em JSON (**ASL — Amazon
States Language**) que define uma sequência de passos: cada passo chama um
serviço AWS (Glue, Lambda, Athena, SQS, SNS...) ou outra máquina de estados.

Por que usar para ETL?

- **Sequência confiável:** Bronze só roda depois que a ingestão terminou; a
  Prata só depois da Bronze; etc.
- **Sem servidor para manter:** você escreve só a definição.
- **Retries e tratamento de erro nativos:** `Retry`/`Catch` por tipo de erro.
- **Observabilidade:** a UI mostra cada execução, qual passo falhou e por quê.
- **Integração direta com Glue** via padrão `.sync`.

---

## 2. O padrão `.sync` (Run a Job)

O Glue tem uma integração especial: `arn:aws:states:::glue:startJobRun.sync`.
O sufixo **`.sync`** significa que o Step Functions **inicia o job e espera
automaticamente** ele terminar (sucesso ou falha). Sem `.sync`, você iniciaria
o job e teria que construir manualmente um loop de `Wait` + `GetJobRun` +
`Choice` para saber quando acabou — verboso e propenso a erro.

```json
"BronzeIngest": {
  "Type": "Task",
  "Resource": "arn:aws:states:::glue:startJobRun.sync",
  "Parameters": { "JobName": "dev-treinamento-bronze_ingest" },
  "Next": "SilverTransform"
}
```

Assim, um pipeline de 3 estágios fica com 3 tarefas `.sync` encadeadas — muito
mais limpo que gerenciar polls manualmente.

---

## 3. Tratamento de erro: Retry e Catch

```json
"Retry": [
  {
    "ErrorEquals": ["States.Timeout", "Glue.ConcurrentRunsExceededException"],
    "IntervalSeconds": 30,
    "MaxAttempts": 2,
    "BackoffRate": 2.0
  }
],
"Catch": [
  { "ErrorEquals": ["States.ALL"], "Next": "PipelineFalhou", "ResultPath": "$.erro" }
]
```

- **Retry:** tenta de novo em erros transitórios (ex.: limite de runs
  concorrentes), com backoff exponencial.
- **Catch:** em qualquer outro erro, desvia para um estado de falha (que pode
  disparar um SNS/Slack).

Boa prática: **não** dê `Retry` cego em `States.ALL` para erros de negócio
(dado inválido) — isso só atrasa a falha. Reserve retry para erros
transitórios.

---

## 4. Estados essenciais (resumo da ASL)

| Tipo | Para quê |
|---|---|
| `Task` | Executar um serviço (Glue, Lambda...). O mais comum. |
| `Choice` | Ramificar (if/else). Ex.: se SUCCEEDED vai a Silver, senão a Falhou. |
| `Parallel` | Executar ramos em paralelo. |
| `Map` | Iterar sobre uma lista (ex.: um job por arquivo). |
| `Wait` | Esperar um tempo fixo ou até um timestamp. |
| `Pass` | Repassa a entrada (útil para moldar JSON). |
| `Succeed` / `Fail` | Termina a execução com sucesso/falha. |

---

## 5. O pipeline completo (Bronze → Prata → Ouro)

O arquivo `terraform/modules/step_function_pipeline/statemachine.asl.json.tpl`
define exatamente:

```
StartAt: BronzeIngest
BronzeIngest (.sync)  --ok-->  SilverTransform
SilverTransform (.sync) --ok--> GoldAggregate
GoldAggregate (.sync) --ok-->  PipelineOk (Succeed)
qualquer erro --> PipelineFalhou (Fail)
```

Cada estágio tem `Retry` (transitórios) e `Catch` (desvia para `Fail`).
Os nomes dos jobs vêm de variáveis do Terraform (`bronze_job`, etc.).

---

## 6. Permissões: a role do Step Functions

Para o Step Functions iniciar um job Glue, a role dele precisa de:

- `glue:StartJobRun`, `glue:GetJobRun`, `glue:GetJobRuns`, `glue:BatchStopJobRun`
  (no(s) job(s)).
- **`iam:PassRole`** sobre a role do Glue (com condição
  `iam:PassedToService = glue.amazonaws.com`) — porque o job usa uma role de
  serviço, e quem inicia precisa "passar" essa role.
- Permissões de logs (se logging habilitado).

Isso está em `terraform/modules/step_function_pipeline/main.tf`.

---

## 7. Agendamento (EventBridge Scheduler)

Para rodar automaticamente, o módulo cria (quando `enable_schedule = true`)
um agendamento **EventBridge Scheduler** que chama `states:StartExecution`:

```hcl
resource "aws_scheduler_schedule" "this" {
  schedule_expression = "cron(0 2 * * ? *)"   # diário às 02h
  target {
    arn      = aws_sfn_state_machine.this.arn
    role_arn = aws_iam_role.schedule[0].arn
  }
}
```

> **Cuidado com custos:** o Step Functions cobra por **transição de estado**.
  Para pipelines que rodam a cada minuto, isso pode somar; para ETL diário,
  o custo é trivial.

---

## 8. Como disparar manualmente e observar

Após `terraform apply`:

```bash
# Dispara uma execução
aws stepfunctions start-execution \
  --state-machine-arn <arn-da-maquina> \
  --input '{}'

# Veja execuções
aws stepfunctions list-executions --state-machine-arn <arn>

# Detalhe de uma execução (qual passo está/errou)
aws stepfunctions describe-execution --execution-arn <arn>
```

Na **UI do Step Functions** (console) você vê o grafo colorido: verde nos
passos concluídos, vermelho nos que falharam, com o erro ao clicar.

---

## Exercícios do módulo

**Ex. 1 — Leia a ASL:** Abra `statemachine.asl.json.tpl`. Identifique os
estados `Task`, o `Succeed` e o `Fail`. Por que **não** há estados `Wait`?
(Resposta no rodapé.) ¹

**Ex. 2 — Disparo manual:** Após aplicar o Terraform (dev), dispare uma
execução pelo console e observe Bronze → Silver → Gold colorindo em verde.

**Ex. 3 — Tratamento de falha:** Force a falha do job Silver (ex.: aponte
`SILVER_PATH` para um bucket inválido temporariamente). Veja o estado
`PipelineFalhou` acender e o Bronze ter ficado verde. Restaure e rode de novo.

**Ex. 4 — Retry transitório:** Adicione `Retry` também para o erro
`Glue.AWSGlueException`. Justifique quando isso ajuda e quando mascara
problemas de dados.

**Ex. 5 — Paralelismo:** Refatore o ASL para que, **depois** do Bronze, duas
transformações independentes rodem em paralelo (ex.: Silver de vendas **e**
Silver de devoluções) usando `Parallel`. Cada uma só avança ao Ouro depois de
ambas terminarem.

**Ex. 6 — Alerta:** Adicione um estado que, em caso de `PipelineFalhou`,
publique num tópico SNS (use `arn:aws:states:::sns:Publish`). Crie o tópico
por Terraform e inscreva seu e-mail.

**Ex. 7 — Map:** Se houver múltiplas tabelas-fonte (vendas, clientes,
produtos), use um estado `Map` para rodar o Bronze de cada uma em paralelo,
e só depois rodar o Silver.

¹ *Porque usamos o padrão `.sync` (`glue:startJobRun.sync`): o próprio Step
Functions faz o polling interno e só avança quando o job termina. `Wait` só
seria necessário se usássemos a versão assíncrona (`startJobRun` sem `.sync`)
e tivéssemos que verificar manualmente o status.*
