#!/bin/bash

# a really dumb way to mirror dockerhub images to private ecr 
aws ecr create-repository --repository-name try-spinnaker-io-nginx
aws ecr get-login-password --region us-east-2 | docker login --username AWS --password-stdin 602961672324.dkr.ecr.us-east-2.amazonaws.com        

docker pull nginx:latest
docker tag nginx:latest 602961672324.dkr.ecr.us-east-2.amazonaws.com/try-spinnaker-io-nginx:latest
docker push 602961672324.dkr.ecr.us-east-2.amazonaws.com/try-spinnaker-io-nginx:latest