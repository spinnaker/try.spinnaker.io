#!/bin/bash
aws eks update-kubeconfig \
  --region us-east-2 \
  --name $1
cd ../spinnaker-kustomize-patches/

# install load balancer controller
kubectl apply --validate=false -f https://github.com/jetstack/cert-manager/releases/download/v1.0.2/cert-manager.yaml
sed -i "s/cluster-name=.*/cluster-name=$1/" v2_2_0_full.yaml
kubectl apply -f v2_2_0_full.yaml

# install spinnaker operator
SPIN_FLAVOR=oss bash ./deploy.sh