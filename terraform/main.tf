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
}

data "aws_availability_zones" "available" {
}

locals {
  cluster_name = "spinnaker-eks-${random_string.suffix.result}"
}

resource "random_string" "suffix" {
  length  = 8
  special = false
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 2.47"

  name                 = "spinnaker-vpc"
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
  #subnets         = module.vpc.private_subnets
  subnets         = concat(module.vpc.public_subnets, module.vpc.private_subnets)
  tags = {
    Environment = "dev"
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
      # additional_security_group_ids = [aws_security_group.allow_lb_to_workers.id]
    },
    # {
    #   name                          = "worker-group-2"
    #   instance_type                 = "t3.small"
    #   additional_userdata           = "echo foo bar"
    #   additional_security_group_ids = [aws_security_group.worker_group_mgmt_two.id]
    #   asg_desired_capacity          = 1
    # },
  ]

  worker_additional_security_group_ids = ["${aws_security_group.allow_lb_to_workers.id}"]
}

resource "aws_s3_bucket" "bucket-2021" {
  bucket = "spinnaker-s3-2021"
  acl    = "private"
  force_destroy = true
  tags = {
    Name = "spinnaker-s3-2021"
  }
}

resource "aws_iam_role_policy_attachment" "s3-full" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
  role       = module.eks.worker_iam_role_name
}

/////////////////////////// Networking stuffs ////////////////////////////////////////////
variable "namespace" {
  default = "spinnaker"
}

variable "public_facing" {
  default = true
}

resource "aws_iam_policy" "AWSLoadBalancerControllerIAMPolicy" {
  name        = "AWSLoadBalancerControllerIAMPolicy"
  description = "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.2.0/docs/install/iam_policy.json"
  policy      = file("policy/AWSLoadBalancerControllerIAMPolicy.json")
}

resource "aws_iam_role_policy_attachment" "aws-lbc-attach" {
  role       = module.eks.worker_iam_role_name
  policy_arn = aws_iam_policy.AWSLoadBalancerControllerIAMPolicy.arn
}

data "aws_route53_zone" "zone" {
  # prvoider = aws.
  # name = "spinnaker.io"
  name = "gsoc.armory.io"
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

resource "aws_security_group" "allow_443" {
  name        = "allow_443"
  description = "Allow TCP on 443 inbound traffic"
  vpc_id      = module.vpc.vpc_id
  ingress {
    description = "Allow 443 TLS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "Allow 80 TLS"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
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

resource "aws_security_group" "allow_lb_to_workers" {
  name        = "allow_lb_to_workers"
  description = "Allow ALB to talk to EC2 worker nodes"
  vpc_id      = module.vpc.vpc_id
  ingress {
    description = "Allow all from ALB"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    security_groups = ["${aws_security_group.allow_443.id}"]
  }
}


resource "aws_acm_certificate" "cert" {
  domain_name       = "try.gsoc.armory.io"
  validation_method = "DNS"
}

resource "aws_acm_certificate_validation" "cert" {
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [for record in aws_route53_record.validation_record : record.fqdn]
}

resource "aws_route53_record" "endpoint" {
  zone_id = data.aws_route53_zone.zone.id
  name = "try.gsoc.armory.io"
  records = [
    kubernetes_ingress.alb.status.0.load_balancer.0.ingress.0.hostname
  ]
  ttl = 600
  type = "CNAME"
} 
// depends on spin-deck
resource "kubernetes_service" "spin-deck" {
  metadata {
    labels = {
      app     = "spin"
      cluster = "spin-deck"
    }
    name      = "spin-deck-custom"
    namespace = var.namespace
    annotations = {
      "alb.ingress.kubernetes.io/healthcheck-protocol" = "HTTP"
      "alb.ingress.kubernetes.io/backend-protocol"     = "HTTP"
    }
  }
  spec {
    port {
      port     = 9000
      protocol = "TCP"
    }
    selector = {
      app     = "spin"
      cluster = "spin-deck"
    }
    type = "NodePort"
  }

  depends_on  = [
    null_resource.spinnaker-operator, module.eks
  ]
}

resource "kubernetes_service" "spin-gate" {
  metadata {
    labels = {
      app     = "spin"
      cluster = "spin-gate"
    }
    name      = "spin-gate-custom"
    namespace = var.namespace
    annotations = {
      "alb.ingress.kubernetes.io/healthcheck-protocol" = "HTTP"
      "alb.ingress.kubernetes.io/backend-protocol"     = "HTTP"
    }
  }
  spec {
    port {
      port     = 8084
      protocol = "TCP"
    }
    selector = {
      app     = "spin"
      cluster = "spin-gate"
    }
    type = "NodePort"
  }
  
  depends_on  = [
    null_resource.spinnaker-operator, module.eks
  ]

}

resource "kubernetes_ingress" "alb" {
  metadata {
    name      = "spinnaker-ingress"
    namespace = var.namespace
    annotations = {
      "kubernetes.io/ingress.class"                        = "alb"
      "alb.ingress.kubernetes.io/tags"                     = "Name=spinnaker-ingress"
      "alb.ingress.kubernetes.io/scheme"                   = var.public_facing ? "internet-facing" : "internal"
      "alb.ingress.kubernetes.io/certificate-arn"          = aws_acm_certificate.cert.arn
      "alb.ingress.kubernetes.io/listen-ports"             = "[{\"HTTPS\":443},{\"HTTP\": 80}]"
      "alb.ingress.kubernetes.io/load-balancer-attributes" = "routing.http2.enabled=true"
      "alb.ingress.kubernetes.io/actions.denied-access"    = "{\"Type\":\"fixed-response\",\"FixedResponseConfig\":{\"ContentType\":\"text/plain\",\"StatusCode\":\"401\",\"MessageBody\":\"NotAllowed\"}}"
      "alb.ingress.kubernetes.io/security-groups"          = aws_security_group.allow_443.id
      "alb.ingress.kubernetes.io/success-codes"            = "404,200"
      "alb.ingress.kubernetes.io/actions.ssl-redirect"     = "{\"Type\":\"redirect\", \"RedirectConfig\": { \"Protocol\": \"HTTPS\", \"Port\": \"443\", \"StatusCode\": \"HTTP_301\"}}"
      "alb.ingress.kubernetes.io/waf-acl-id"               = null
    }
  }
  wait_for_load_balancer = true
  spec {
    rule {
      http {
        path {
          path = "/api/v1/*"
          backend {
            service_name = kubernetes_service.spin-gate.metadata.0.name
            service_port = "8084"
          }
        }
        path {
          path = "/*"
          backend {
            service_name = kubernetes_service.spin-deck.metadata.0.name
            service_port = "9000"
          }
        }
      }
    }
  }

  depends_on  = [
    helm_release.aws-load-balancer
  ]
}


provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.cluster.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
    exec {
      api_version = "client.authentication.k8s.io/v1alpha1"
      args        = ["eks", "get-token", "--cluster-name", data.aws_eks_cluster.cluster.name]
      command     = "aws"
    }
  }
}

resource "helm_release" "aws-load-balancer" {
  name       = "aws-load-balancer-controller"

  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  set {
    name = "clusterName"
    value =  data.aws_eks_cluster.cluster.name
  }

  depends_on = [
    aws_iam_role_policy_attachment.aws-lbc-attach, module.vpc
  ]
}

# taint?
resource "null_resource" "spinnaker-operator" {
  provisioner "local-exec" {
    command = "cd ../spinnaker-kustomize-patches && SPIN_FLAVOR=oss SPIN_WATCH=0 bash ./deploy.sh"
  }
  depends_on = [
    helm_release.aws-load-balancer, aws_s3_bucket.bucket-2021
  ]
}

resource "null_resource" "update-kubectl-config" {
  provisioner "local-exec" {
    command = "aws eks update-kubeconfig --region us-east-2 --name ${data.aws_eks_cluster.cluster.name}"
  }
}

resource "aws_ecr_repository" "try-spinnaker-io-nginx" {
  name                 = "try-spinnaker-io-nginx"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_iam_role_policy_attachment" "ec2-read-ecr" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = module.eks.worker_iam_role_name
}

# resource "null_resource" "mirror-dockerhub-to-ecr" {
#   provisioner "local-exec" {
#     command = "bash ../spinnaker-kustomize-patches/ecr.sh"
#   }

#   depends_on = [
#     aws_ecr_repository.ecr
#   ]
# }