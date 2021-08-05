resource "aws_s3_bucket" "generated_metric_images_bucket" {
  bucket_prefix = "${var.name-of-bucket-to-store-images}-"
  acl           = "public-read"
  force_destroy = true
}

resource "aws_s3_bucket_policy" "generated_metric_images_bucket_policy" {
  bucket = aws_s3_bucket.generated_metric_images_bucket.id

  policy = data.aws_iam_policy_document.iam_resource_policy_for_generated_metric_images_bucket.json
}

data "aws_iam_policy_document" "iam_resource_policy_for_generated_metric_images_bucket" {
  statement {
    effect = "Allow"

    actions = [
      "s3:*"
    ]

    principals {
      type        = "AWS"
      identifiers = ["${data.aws_caller_identity.current.account_id}", "${var.role-arn-of-generate-metric-image-fn}"]
    }


    resources = [
      "${aws_s3_bucket.generated_metric_images_bucket.arn}",
      "${aws_s3_bucket.generated_metric_images_bucket.arn}/*",
    ]
  }
}

output "bucket_id" {
  value = aws_s3_bucket.generated_metric_images_bucket.id
}