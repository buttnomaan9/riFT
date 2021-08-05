/*resource "aws_iam_user" "aws_api_gateway_user" {
  name = var.api-gateway-user-name
  tags = {
    type = "service"
  }
}

resource "aws_iam_access_key" "aws_api_gateway_user_key" {
  user = aws_iam_user.aws_api_gateway_user.name
}

resource "aws_iam_user_policy" "aws_api_gateway_user_policy" {
  name = var.api-gateway-user-name
  user = aws_iam_user.aws_api_gateway_user.name

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "execute-api:*"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
EOF
}*/