#!/bin/bash

# spin setup

spin --config ~/.spin/oauth application save --application-name cleanup --owner-email danielhbko@gmail.com --cloud-providers "kubernetes"
spin --config ~/.spin/oauth pipeline save --file pipelines/delete-resources.json

spin --config ~/.spin/oauth application save --application-name web-app --owner-email danielhbko@gmail.com --cloud-providers "kubernetes"
sleep 4
spin --config ~/.spin/oauth pipeline save --file pipelines/deploy-app.json