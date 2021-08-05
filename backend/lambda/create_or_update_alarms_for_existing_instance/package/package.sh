#!/bin/bash +xe
DEPLOYMENT_PATH="../../../../../deployment/terraform/services/"
SERVICE="create-or-update-alarms-for-existing-instance"
rm -rf $DEPLOYMENT_PATH/$SERVICE/src
mkdir -p $DEPLOYMENT_PATH/$SERVICE/src
cp ../lambda_function.py $DEPLOYMENT_PATH/$SERVICE/src