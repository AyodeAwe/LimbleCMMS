resource "aws_efs_file_system" "wpefs" {
  creation_token = "wordpressefs"

  tags = {
    Name = "wordpress-efs"
  }
}