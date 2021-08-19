#!/bin/bash

# pipeline setup

spin --config ~/.spin/oauth application save --application-name cleanup --owner-email danielhbko@gmail.com --cloud-providers "kubernetes"
sleep 4
spin --config ~/.spin/oauth pipeline save --file pipelines/delete-resources.json
sleep 4

spin --config ~/.spin/oauth application save --application-name web-app --owner-email danielhbko@gmail.com --cloud-providers "kubernetes"
sleep 4
spin --config ~/.spin/oauth pipeline save --file pipelines/deploy-app.json
sleep 4

spin --config ~/.spin/oauth application save --application-name Trigger --owner-email danielhbko@gmail.com --cloud-providers "kubernetes"
sleep 4
spin --config ~/.spin/oauth pipeline save --file pipelines/trigger-cron.json
sleep 4
spin --config ~/.spin/oauth pipeline save --file pipelines/trigger-git.json
sleep 4
spin --config ~/.spin/oauth pipeline save --file pipelines/trigger-webhook.json
sleep 4

spin --config ~/.spin/oauth application save --application-name Highlander --owner-email danielhbko@gmail.com --cloud-providers "kubernetes"
sleep 4
spin --config ~/.spin/oauth pipeline save --file pipelines/highlander.json
