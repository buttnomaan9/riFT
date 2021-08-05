#!/bin/bash +xe
DEPLOYMENT_PATH="../../../../../deployment/terraform/services/"
SERVICE="post-alarm-state-to-email"
rm -rf $DEPLOYMENT_PATH/$SERVICE/src
mkdir -p $DEPLOYMENT_PATH/$SERVICE/src
cp ../lambda_function.py $DEPLOYMENT_PATH/$SERVICE/src