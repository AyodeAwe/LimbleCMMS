variable "ecr_repo_name" {
    type    = string
    default = "limblecmms-repo"
}

variable "service_name" {
    type    = string
    default = "limblecmms-svc"
}

variable "region" {
    default = "eu-west-1"
    type    = string
}

variable "region" {
    default = "eu-west-1"
    type    = string
}

variable "container_port" {
    default = 80
    type    = number
}