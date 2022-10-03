terraform {
  backend "s3" {
    bucket         = "wp-ecs-backend"
    key            = "terraform.tfstate"
    region         = "eu-west-1"
    dynamodb_table = "tf_ecs_state"
  }
}