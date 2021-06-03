# Notes
.tf files inspired from [terraform-aws-eks/examples][] 

TODO:
- [ ] Research auto scaling  
- [ ] Research spot instances 
- [ ] ELB + DNS
## Setup
- Install [awscli][]
  - Create [access key]
  - Input keys here `aws configure` 
- Install [Terraform][]
- Install kubectl

## Run 
- Clone this repo 
### Terraform
- Inside this repo run the following Terraform commands
  - `terraform init` 
  - `terraform plan` 
  - `terraform apply` 

### kubeconfig
- Add `export KUBECONFIG=/home/<your_username>/.kube/config` to ~/.zshrc or ~/.bash_profile if missing
- Run to update kubeconfig
  ```
  aws eks update-kubeconfig \
  --region us-east-2 \
  --name <name-of-eks-cluster-you-defined>
  ```
More info for accessing [eks through kubectl][]

## Deploy to Cluster
Check under EKS/Clusters/name-of-cluster/workloads in AWS console to see deployments
### nginx
`kubectl create deployment nginx --image=nginx`
### Kubernetes dashboard
#### Deploy dashboard
`kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.0.5/aio/deploy/recommended.yaml`
#### Create Service Account 
`kubectl apply -f eks-admin-service-account.yaml`
#### Connect to the dashboard
- Get the auth token for eks-admin via 
`kubectl -n kube-system describe secret $(kubectl -n kube-system get secret | grep eks-admin | awk '{print $1}')`
- Start proxy `kubectl proxy`
- Navigate to `http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/#!/login`
- Login with the auth token


More info for [Kubernetes dashboard][]

## Teardown
Don't forget to 
`terraform destroy`

[awscli]: https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2-linux.html
[access key]: https://console.aws.amazon.com/iam/home?#/security_credentials
[Terraform]: https://learn.hashicorp.com/tutorials/terraform/install-cli
[eks through kubectl]: https://docs.aws.amazon.com/eks/latest/userguide/getting-started-console.html#eks-configure-kubectl
[Kubernetes dashboard]: https://docs.aws.amazon.com/eks/latest/userguide/dashboard-tutorial.html
[terraform-aws-eks/examples]: https://github.com/terraform-aws-modules/terraform-aws-eks/tree/master/examples/basic 
