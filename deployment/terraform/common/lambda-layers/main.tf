resource "aws_lambda_layer_version" "lambda_layer_aws_lambda_powertools_and_more" {
  filename            = data.archive_file.aws_lambda_powertools_and_more_layer_lambda_zip.output_path
  layer_name          = "${local.name-prefix}-aws-lambda-powertools-and-more"
  compatible_runtimes = ["python3.8"]
  source_code_hash    = data.archive_file.aws_lambda_powertools_and_more_layer_lambda_zip.output_base64sha256
}

data "archive_file" "aws_lambda_powertools_and_more_layer_lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/packages/aws-powertools-and-more/src/"
  output_path = "${path.module}/packages/aws-powertools-and-more/dist/powertools.zip"
}

output "layer_arn" {
  value = aws_lambda_layer_version.lambda_layer_aws_lambda_powertools_and_more.arn
}