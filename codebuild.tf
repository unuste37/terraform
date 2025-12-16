resource "aws_s3_bucket" "codepipeline_bucket" {
  bucket        = "${var.project_name}-artifacts-${random_id.suffix.hex}"
  force_destroy = true
  tags          = local.tags
}

resource "random_id" "suffix" {
  byte_length = 3
}

resource "aws_iam_role" "codebuild_role" {
  name = "${var.project_name}-cb-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "sts:AssumeRole"
      Principal = {
        # *** CORRECTION HERE ***
        # The Principal should be an array (list) of services allowed to assume the role.
        # We need to add "codepipeline.amazonaws.com" to resolve the error.
        Service = [
          "codepipeline.amazonaws.com",
          "codebuild.amazonaws.com"
        ]
      }
    }]
  })
}

# NOTE: Using "AdministratorAccess" is a broad permission. 
# While convenient for labs, use specific policies (like AWSCodePipelineServiceRole, 
# AWSCodeBuildDeveloperAccess, etc.) in production environments.
resource "aws_iam_role_policy_attachment" "codebuild_attach" {
  role       = aws_iam_role.codebuild_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_codebuild_project" "terraform_build" {
  name         = "${var.project_name}-build"
  service_role = aws_iam_role.codebuild_role.arn
  source {
    type      = "GITHUB"
    location  = "https://github.com/unuste37/terraform"
    buildspec = "buildspec.yml"
  }
  artifacts {
    type = "NO_ARTIFACTS"
  }
  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/standard:7.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = true
  }
}

resource "aws_codepipeline" "terraform_pipeline" {
  name     = "${var.project_name}-pipeline"
  role_arn = aws_iam_role.codebuild_role.arn

  artifact_store {
    type     = "S3"
    location = aws_s3_bucket.codepipeline_bucket.bucket
  }

  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "ThirdParty"
      provider         = "GitHub"
      version          = "1"
      output_artifacts = ["source_output"]
      configuration = {
        Owner  = "unuste37"
        Repo   = "terraform"
        Branch = "main"
        #OAuthToken = var.github_token
        OAuthToken = "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"
      }
    }
  }

  stage {
    name = "Build"
    action {
      name            = "Terraform"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      input_artifacts = ["source_output"]
      version         = "1"
      configuration = {
        ProjectName = aws_codebuild_project.terraform_build.name
      }
    }
  }
}
