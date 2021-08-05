#!/bin/bash +xe
DEPLOYMENT_PATH="../../../../../deployment/terraform/services/"
SERVICE="suppress-notifcation-or-generate-metric-images"
rm -rf $DEPLOYMENT_PATH/$SERVICE/src
mkdir -p $DEPLOYMENT_PATH/$SERVICE/src
mkdir -p $DEPLOYMENT_PATH/$SERVICE/src/util
cp ../lambda_function.py $DEPLOYMENT_PATH/$SERVICE/src
cp -rp ../../util/ $DEPLOYMENT_PATH/$SERVICE/src/util