{
  "Comment": "Pipeline medalhão: Bronze -> Prata -> Ouro. Usa o padrao .sync do Step Functions (espera o job concluir automaticamente).",
  "StartAt": "BronzeIngest",
  "States": {
    "BronzeIngest": {
      "Type": "Task",
      "Resource": "arn:aws:states:::glue:startJobRun.sync",
      "Parameters": {
        "JobName": "${bronze_job}"
      },
      "Retry": [
        {
          "ErrorEquals": ["States.Timeout", "Glue.ConcurrentRunsExceededException"],
          "IntervalSeconds": 30,
          "MaxAttempts": 2,
          "BackoffRate": 2.0
        }
      ],
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "Next": "PipelineFalhou",
          "ResultPath": "$.erro"
        }
      ],
      "Next": "SilverTransform"
    },
    "SilverTransform": {
      "Type": "Task",
      "Resource": "arn:aws:states:::glue:startJobRun.sync",
      "Parameters": {
        "JobName": "${silver_job}"
      },
      "Retry": [
        {
          "ErrorEquals": ["States.Timeout", "Glue.ConcurrentRunsExceededException"],
          "IntervalSeconds": 30,
          "MaxAttempts": 2,
          "BackoffRate": 2.0
        }
      ],
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "Next": "PipelineFalhou",
          "ResultPath": "$.erro"
        }
      ],
      "Next": "GoldAggregate"
    },
    "GoldAggregate": {
      "Type": "Task",
      "Resource": "arn:aws:states:::glue:startJobRun.sync",
      "Parameters": {
        "JobName": "${gold_job}"
      },
      "Retry": [
        {
          "ErrorEquals": ["States.Timeout", "Glue.ConcurrentRunsExceededException"],
          "IntervalSeconds": 30,
          "MaxAttempts": 2,
          "BackoffRate": 2.0
        }
      ],
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "Next": "PipelineFalhou",
          "ResultPath": "$.erro"
        }
      ],
      "Next": "PipelineOk"
    },
    "PipelineOk": {
      "Type": "Succeed"
    },
    "PipelineFalhou": {
      "Type": "Fail",
      "Error": "PipelineMedalhaoFalhou",
      "Cause": "Um dos jobs Glue (bronze/prata/ouro) falhou. Verifique os logs no CloudWatch."
    }
  }
}
