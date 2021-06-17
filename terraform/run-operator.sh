#!/bin/bash
aws eks update-kubeconfig \
  --region us-east-2 \
  --name $1

cd ../spinnaker-kustomize-patches/
SPIN_FLAVOR=oss bash ./deploy.sh