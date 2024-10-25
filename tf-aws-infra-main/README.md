# tf-aws-infra

Terraform configurations for an AWS VPC with 3 private subnets and 3 public subnets along with route tables and an internet gateway. The configuration builds an infrastructure with a custom Amazon Machine Image built using Packer, an EC2 instance and Amazon RDS which deploys a PostgreSQL DB.

Continuous Integration is implement using Github Actions and Workflow.
