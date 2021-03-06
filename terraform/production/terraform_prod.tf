variable "previous_commit_id" {
  type        = string
  description = "Previous commit id to enable rollback."
}

# Region
provider "aws" {
  region = "eu-west-1"
}


# Data resources (SQS, SSM)
data "aws_sqs_queue" "prod-processed-job-post-queue" {
  name = "prod_ProcessedJobPosts"
}


data "aws_ssm_parameter" "slackleads-table" {
  name = "TABLE_SLACK_LEADS" # our SSM parameter's name
}

data "aws_ssm_parameter" "slackskills-table" {
  name = "TABLE_SLACK_SKILLS" # our SSM parameter's name
}

data "aws_ssm_parameter" "slack-token" {
  name = "SLACK_TOKEN" # our SSM parameter's name
}

data "aws_ssm_parameter" "close-token" {
  name = "CLOSE_TOKEN" # our SSM parameter's name
}

data "aws_ssm_parameter" "slack-verification-token" {
  name = "SLACK_VERIFICATION_TOKEN" # our SSM parameter's name
}


# Lambda
resource "aws_lambda_function" "prod-SlackJobPoster-lambda" {
  function_name    = "prod-SlackJobPoster"
  handler          = "SlackJobPoster::SlackJobPoster.Function::FunctionHandler"
  runtime          = "dotnetcore2.1"
  role             = "arn:aws:iam::833191605868:role/DeleteThisRole"
  filename         = "../../SlackJobPoster/src/SlackJobPoster/bin/Release/netcoreapp2.1/SlackJobPoster.zip"
  source_code_hash = filebase64sha256("../../SlackJobPoster/src/SlackJobPoster/bin/Release/netcoreapp2.1/SlackJobPoster.zip")
  timeout          = 10
  memory_size      = 256

  tags = {
    Name        = "prod-SlackJobPoster"
    Environment = "production"
  }

  environment {
    variables = {
      CLOSE_TOKEN            = data.aws_ssm_parameter.close-token.value
      AWS_TABLE_SLACK_SKILLS = data.aws_ssm_parameter.slackskills-table.value
    }
  }
}

resource "aws_lambda_event_source_mapping" "prod-incoming-sqs" {
  event_source_arn = data.aws_sqs_queue.prod-processed-job-post-queue.arn
  function_name    = aws_lambda_function.prod-SlackJobPoster-lambda.arn
}

resource "aws_lambda_function" "prod-SlackJobPosterReceiver-lambda" {
  function_name    = "prod-SlackJobPosterReceiver"
  handler          = "SlackJobPosterReceiver::SlackJobPosterReceiver.Function::Get"
  runtime          = "dotnetcore2.1"
  role             = "arn:aws:iam::833191605868:role/DeleteThisRole"
  filename         = "../../SlackJobPosterReceiver/src/SlackJobPosterReceiver/bin/Release/netcoreapp2.1/SlackJobPosterReceiver.zip"
  source_code_hash = filebase64sha256("../../SlackJobPosterReceiver/src/SlackJobPosterReceiver/bin/Release/netcoreapp2.1/SlackJobPosterReceiver.zip")
  timeout          = 10
  memory_size      = 256

  tags = {
    Name        = "prod-SlackJobPosterReceiver"
    Environment = "production"
  }

  environment {
    variables = {
      AWS_TABLE_SLACK_LEADS    = data.aws_ssm_parameter.slackleads-table.value
      AWS_TABLE_SLACK_SKILLS   = data.aws_ssm_parameter.slackskills-table.value
      SLACK_TOKEN              = data.aws_ssm_parameter.slack-token.value
      CLOSE_TOKEN              = data.aws_ssm_parameter.close-token.value
      SLACK_VERIFICATION_TOKEN = data.aws_ssm_parameter.slack-verification-token.value
    }
  }
}


# API Gateway
resource "aws_api_gateway_rest_api" "slack-app-api" {
  name = "slackAppApi-prod"
}

resource "aws_api_gateway_resource" "slack-receiver-resource" {
  path_part   = "slackReceiver"
  parent_id   = aws_api_gateway_rest_api.slack-app-api.root_resource_id
  rest_api_id = aws_api_gateway_rest_api.slack-app-api.id
}

resource "aws_api_gateway_method" "slack-receiver-any" {
  rest_api_id   = aws_api_gateway_rest_api.slack-app-api.id
  resource_id   = aws_api_gateway_resource.slack-receiver-resource.id
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "integration" {
  rest_api_id             = aws_api_gateway_rest_api.slack-app-api.id
  resource_id             = aws_api_gateway_resource.slack-receiver-resource.id
  http_method             = aws_api_gateway_method.slack-receiver-any.http_method
  integration_http_method = "ANY"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.prod-SlackJobPosterReceiver-lambda.invoke_arn
}

resource "aws_api_gateway_deployment" "slack-receiver-api-deployment" {
  depends_on = [aws_api_gateway_integration.integration]

  rest_api_id = aws_api_gateway_rest_api.slack-app-api.id
  stage_name  = "production"
}

# Dynamo DB
resource "aws_dynamodb_table" "prod-slack-leads-table" {
  name           = "prod_SlackLeads"
  hash_key       = "message_ts"
  read_capacity  = 5
  write_capacity = 5

  attribute {
    name = "message_ts"
    type = "S"
  }

  tags = {
    Name        = "prod-slack-leads-table"
    Environment = "production"
  }
}

resource "aws_dynamodb_table" "prod-slack-skills-table" {
  name           = "prod_JobSkillsFilter"
  hash_key       = "skill_name"
  read_capacity  = 5
  write_capacity = 5

  attribute {
    name = "skill_name"
    type = "S"
  }

  tags = {
    Name        = "prod-slack-skills-table"
    Environment = "production"
  }
}


# Cloudwatch
resource "aws_cloudwatch_event_rule" "prod-SlackJobPosterReceiver-rule" {
  name                = "prod-SlackJobPosterReceiver-warmer"
  schedule_expression = "rate(5 minutes)"
}

resource "aws_cloudwatch_event_target" "prod-SlackJobPosterReceiver-target" {
  rule  = aws_cloudwatch_event_rule.prod-SlackJobPosterReceiver-rule.name
  arn   = aws_lambda_function.prod-SlackJobPosterReceiver-lambda.arn
  input = "{\"Resource\":\"WarmingLambda\",\"Body\":\"5\"}"
}

resource "aws_lambda_permission" "allow_cloudwatch_to_call_SlackJobPosterReceiver" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.prod-SlackJobPosterReceiver-lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.prod-SlackJobPosterReceiver-rule.arn
}

resource "aws_cloudwatch_event_rule" "prod-RollbackAlarm-rule" {
  name        = "prod-RollbackAlarm-rule"
  description = "Rollback to previous commit in case an alarm changes state"

  event_pattern = <<PATTERN
{
  "source": [
    "aws.cloudwatch"
  ],
  "resources": [
    "arn:aws:cloudwatch:eu-west-1:833191605868:alarm:HealthCheck Alarm (Production)"
  ],
  "detail-type": [
    "CloudWatch Alarm State Change"
  ],
  "detail": {
    "state": 
    {
      "value": [
                "ALARM"
            ]
    }
  }
}
PATTERN
}

resource "aws_iam_role" "prod-CloudwatchCodebuild-role" {
  name = "prod-CloudwatchCodebuild-role"

  assume_role_policy = <<-EOF
  {
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
              "Service": "events.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
  }
  EOF
}

resource "aws_iam_role_policy" "prod-CloudwatchCodebuild-rolePolicy" {
  name = "prod-CloudwatchCodebuild-rolePolicy"
  role = aws_iam_role.prod-CloudwatchCodebuild-role.id

  policy = <<-EOF
  {
    "Version": "2012-10-17",
    "Statement": [
      {
          "Effect": "Allow",
          "Action": [
              "codebuild:StartBuild"
          ],
          "Resource": "arn:aws:codebuild:eu-west-1:833191605868:project/SlackJobApp-Prod"
      }
    ]
  }
  EOF
}

resource "aws_cloudwatch_event_target" "prod-CloudwatchEventCodebuild" {
  rule     = aws_cloudwatch_event_rule.prod-RollbackAlarm-rule.name
  arn      = "arn:aws:codebuild:eu-west-1:833191605868:project/SlackJobApp-Prod"
  role_arn = aws_iam_role.prod-CloudwatchCodebuild-role.arn
  input    = "{\"sourceVersion\":\"${var.previous_commit_id}\"}"
}