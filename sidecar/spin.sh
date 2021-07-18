#!/bin/bash

# spin setup

spin application save --application-name cleanup --owner-email danielhbko@gmail.com --cloud-providers "kubernetes"
spin pipeline save --file pipelines/delete-resources.json

spin application save --application-name web-app --owner-email danielhbko@gmail.com --cloud-providers "kubernetes"
spin pipeline save --file pipelines/deploy-app.json