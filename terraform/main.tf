provider "aws" {
  region = var.region
}

data "aws_eks_cluster" "cluster" {
  name = module.eks.cluster_id
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_id
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
  token                  = data.aws_eks_cluster_auth.cluster.token
  load_config_file       = false
}

data "aws_availability_zones" "available" {
}

locals {
  cluster_name = "test-eks-${random_string.suffix.result}"
}

resource "random_string" "suffix" {
  length  = 8
  special = false
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 2.47"

  name                 = "test-vpc"
  cidr                 = "10.0.0.0/16"
  azs                  = data.aws_availability_zones.available.names
  private_subnets      = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets       = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  public_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                      = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"             = "1"
  }
}

module "eks" {
  source          = "terraform-aws-modules/eks/aws"
  cluster_name    = local.cluster_name
  cluster_version = "1.20"
  subnets         = module.vpc.private_subnets

  tags = {
    Environment = "test"
    GithubRepo  = "terraform-aws-eks"
    GithubOrg   = "terraform-aws-modules"
  }

  vpc_id = module.vpc.vpc_id

  worker_groups = [
    {
      name                          = "worker-group-1"
      instance_type                 = "t3.xlarge"
      additional_userdata           = "echo foo bar"
      asg_desired_capacity          = 1
      # additional_security_group_ids = [aws_security_group.worker_group_mgmt_one.id]
    },
    # {
    #   name                          = "worker-group-2"
    #   instance_type                 = "t3.small"
    #   additional_userdata           = "echo foo bar"
    #   additional_security_group_ids = [aws_security_group.worker_group_mgmt_two.id]
    #   asg_desired_capacity          = 1
    # },
  ]

  # worker_additional_security_group_ids = [aws_security_group.all_worker_mgmt.id]
}

resource "aws_s3_bucket" "bucket-2021" {
  bucket = "spinnaker-s3-2021"
  acl    = "private"

  tags = {
    Name = "spinnaker-s3-2021"
  }
}

resource "aws_iam_role_policy_attachment" "s3-full" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
  role       = module.eks.worker_iam_role_name
}



resource "aws_route53_record" "validation_record" {
  for_each = {
  for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
    name   = dvo.resource_record_name
    record = dvo.resource_record_value
    type   = dvo.resource_record_type
  }
  }
  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.zone.zone_id
}

data "aws_route53_zone" "zone" {
  # prvoider = aws.
  # name = "spinnaker.io"
  name = "gsoc.armory.io"
}

# resource "aws_route53_record" "endpoint" {
#   zone_id = data.aws_route53_zone.zone.id
#   name = "try.gsoc.armory.io"
#   records = [
#     kubernetes_ingress.alb.load_balancer_ingress[0].hostname
#   ]
#   ttl = 600
#   type = "CNAME"
# } 

variable "namespace" {
    default = "spinnaker"
}
variable "public_facing" {
    default = true
}

resource "aws_security_group" "allow_443" {
  name        = "allow_443"
  description = "Allow TCP on 443 inbound traffic"
  vpc_id      = module.vpc.vpc_id
  ingress {
    description = "Allow TLS from Armory VPN"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
  }
  ingress {
    description = "Allow TLS from Armory VPN"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
  }
  egress {
    description = "Allow The load balancer to talk to anything"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "allow_https"
  }
}
resource "kubernetes_service" "spin-gate" {
  metadata {
    labels = {
      app= "spin"
      cluster= "spin-gate"
    }
    name= "spin-gate-custom"
    namespace= var.namespace
    annotations = {
      "alb.ingress.kubernetes.io/healthcheck-protocol" = "HTTP"
      "alb.ingress.kubernetes.io/backend-protocol" = "HTTP"
    }
  }
  spec {
    port {
      port = 8084
      protocol = "TCP"
    }
    selector = {
      app= "spin"
      cluster= "spin-gate"
    }
    type = "NodePort"
  }
}
variable "x509_port" {
  default = 8443
}
resource "kubernetes_service" "spin-gate-api" {
  metadata {
    labels = {
      app= "spin"
      cluster= "spin-gate"
    }
    name= "spin-gate-api"
    namespace=var.namespace
    annotations = {
      ## Null here removes the annotation when it's public facing.  If the annotation is there at all with ANY value it creates it as private... UGH
      "service.beta.kubernetes.io/aws-load-balancer-internal" = (var.public_facing ? null : "true")
      "service.beta.kubernetes.io/aws-load-balancer-type" = "nlb"
      "service.beta.kubernetes.io/aws-load-balancer-extra-security-groups" = aws_security_group.allow_443.id
    }
  }
  spec {
    port {
      port = var.x509_port
      protocol = "TCP"
    }
    selector = {
      app= "spin"
      cluster= "spin-gate"
    }
    type = "LoadBalancer"
  }
}
resource "kubernetes_service" "spin-deck" {
  metadata {
    labels = {
      app= "spin"
      cluster= "spin-deck"
    }
    name= "spin-deck-custom"
    namespace=var.namespace
    annotations = {
      "alb.ingress.kubernetes.io/healthcheck-protocol" = "HTTP"
      "alb.ingress.kubernetes.io/backend-protocol" = "HTTP"
    }
  }
  spec {
    port {
      port = 9000
      protocol = "TCP"
    }
    selector = {
      app= "spin"
      cluster= "spin-deck"
    }
    type = "NodePort"
  }
}

resource "aws_acm_certificate" "cert" {
  domain_name = "try.gsoc.armory.io"
  validation_method = "DNS"
}

resource "aws_acm_certificate_validation" "cert" {
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [for record in aws_route53_record.validation_record : record.fqdn]
}

resource "kubernetes_ingress" "alb" {
  metadata {
    name = "spinnaker-ingress"
    namespace = var.namespace
    annotations = {
      "kubernetes.io/ingress.class" = "alb"
      "alb.ingress.kubernetes.io/tags" = "Name=spinnaker-ingress"
      "alb.ingress.kubernetes.io/scheme" = var.public_facing ? "internet-facing" : "internal"
      "alb.ingress.kubernetes.io/certificate-arn" = aws_acm_certificate.cert.arn
      "alb.ingress.kubernetes.io/listen-ports" = "[{\"HTTPS\":443},{\"HTTP\": 80}]"
      "alb.ingress.kubernetes.io/load-balancer-attributes" = "routing.http2.enabled=true"
      "alb.ingress.kubernetes.io/actions.denied-access" = "{\"Type\":\"fixed-response\",\"FixedResponseConfig\":{\"ContentType\":\"text/plain\",\"StatusCode\":\"401\",\"MessageBody\":\"NotAllowed\"}}"
      "alb.ingress.kubernetes.io/security-groups" = aws_security_group.allow_443.id
      "alb.ingress.kubernetes.io/success-codes" = "404,200"
      "alb.ingress.kubernetes.io/actions.ssl-redirect" = "{\"Type\":\"redirect\", \"RedirectConfig\": { \"Protocol\": \"HTTPS\", \"Port\": \"443\", \"StatusCode\": \"HTTP_301\"}}"
      "alb.ingress.kubernetes.io/waf-acl-id" = null
    }
  }
  spec {
    rule {
      http {
        path {
          path = "/api/v1/*"
          backend {
            service_name = "${kubernetes_service.spin-gate.metadata[0].labels.cluster}-custom"
            service_port = "8084"
          }
        }
        path {
          path = "/*"
          backend {
            service_name = "${kubernetes_service.spin-deck.metadata[0].labels.cluster}-custom"
            service_port = "9000"
          }
        }
       }
      }
    }
}

# output "api_dns" {
#   value = kubernetes_service.spin-gate-api.load_balancer_ingress
# }
output "lb_dns" {
  value = kubernetes_ingress.alb.load_balancer_ingress
}