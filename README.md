# try.spinnaker.io

try.spinnaker.io is a hosted playground version of [Spinnaker][] aimed for new users to test out its UI and core features. 

## Features

- IaC via Terraform to host try.spinnaker.io on AWS using an EKS cluster
- Deployment of Spinnaker via Armory's OOS [Spinnaker Operator][]
- Kubernetes deployment via Spinnaker
- AWS Load Balancer Controller to expose deployments
- User authentication via Google OAuth 2.0
- Private ECR registry
- Block all public images via [portieris][]
- Script to deploy default pipelines
  - Auto resource cleanup 
  - Deploy demo web app
  - Deploy using [highlander][] strategy 
- Authz rules via a Spinnaker [plugin][], adds default role 'public' to all users
- ~~Metrics~~(wip)

## Requirements 
- [awscli][]
  - Create [access key][]
  - Input keys here `aws configure` 
- [Route53 hosted zone][]
- [Terraform][]
- kubectl (v1.20.0), new verisons break kustomize script for Spinnaker operator
  - `curl -LO "https://dl.k8s.io/v1.20.0/bin/linux/amd64/kubectl"`
- [Google OAuth 2.0 Client ID][]

## Configuration
### Terraform 
Edit the values `region`, `route53_zone`, and `domain_name` in `terraform/variables.tf`. Note: `domain_name` must be a subdomain of `route53_zone`, i.e. if `route53_zone = spinnaker.io` `then domain_name = try.spinnaker.io`.
### Spinnaker Operator
Files are inside the `spinnaker-kustomize-patches` folder.
| File Name                     | Description  |
| ----------------------------- | ------------ |
| kustomization.yml | Main kustomize file.  |
| spinnakerservice.yml | Contains configuration for Spinnaker. <br><br> Update `spec.spinnakerConfig.config.version` to the version of OOS Spinnaker you wish to deploy. <br><br> Update the value of `https://try.gsoc.armory.io` in `spec.spinnakerConfig.config.*.apiSecurity.overrideBaseUrl` to your DNS name. |
| security/patch-file-authz.yml | Update `users.username` to the admin email you will login with Google OAuth in `spec.spinnakerConfig.files.rolemappings.yml` |
| security/patch-google.yml | Update `spec.spinnakerConfig.config.security.authn.client.clientId` to your Google OAuth 2.0 Client ID. <br><br> Create a file called `spinnaker-kustomize-patches/secrets/secrets.env` and add your Secret ID to the file in in this format` oauth-client-secret=fakepassword123` |
| accounts/docker/patch-ecr.yml                  | Update `spec.spinnakerConfig.providers.dockerRegistry.accounts.address` to the address of your ECR registry. |


## Run
Run these commands in the terraform folder.
```
terraform init
terraform plan
terraform apply
```
### Inject Default Pipelines
- Install [spin][], a cli tool for Spinnnaker.
- Copy the file `scripts/oauth` to `~/.spin/oauth`
- Modify `Gate.Endpoint`, `ClientId`, and `ClientSecret`
- Run script via `bash scripts/spin.sh`

### Shutdown
When you are all done then run:
```
terraform destroy
```
You may need to go into AWS Web Console to delete dangling load balancers or VPC in the case that Terraform doesn't delete it. 

[Spinnaker]: https://spinnaker.io/
[highlander]: https://spinnaker.io/docs/guides/user/kubernetes-v2/rollout-strategies/#highlander-rollouts
[Spinnaker Operator]: https://github.com/armory/spinnaker-operator
[portieris]: https://github.com/IBM/portieris
[awscli]: https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2-linux.html
[access key]: https://console.aws.amazon.com/iam/home?#/security_credentials
[Terraform]: https://learn.hashicorp.com/tutorials/terraform/install-cli
[Google OAuth 2.0 Client ID]: https://support.google.com/cloud/answer/6158849?hl=en
[Route53 hosted zone]: https://aws.amazon.com/route53/faqs/#:~:text=A%20hosted%20zone%20is%20an,domain%20name%20as%20a%20suffix
[spin]: https://spinnaker.io/docs/setup/other_config/spin/
[plugin]: https://github.com/ko28/defaultRolePlugin