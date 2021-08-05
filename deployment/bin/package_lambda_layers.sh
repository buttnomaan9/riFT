
#!/bin/bash +xe
### lambda-layers ###
DEPLOYMENT_PATH="../../deployment/terraform/common"
SHARED_RESOURCE_CATEGORY="lambda-layers"
PACKAGE="aws-powertools-and-more"
echo "### Empty and create src folder for $PACKAGE. ###"
rm -rf $DEPLOYMENT_PATH/$SHARED_RESOURCE_CATEGORY/packages/$PACKAGE/src/
mkdir -p $DEPLOYMENT_PATH/$SHARED_RESOURCE_CATEGORY/packages/$PACKAGE/src/python/lib/python3.8/site-packages/

echo "### Download python dependencies for $PACKAGE. ###"
pip3 install aws-lambda-powertools -t $DEPLOYMENT_PATH/$SHARED_RESOURCE_CATEGORY/packages/$PACKAGE/src/python/lib/python3.8/site-packages/

echo "### Download boto3-stubs module. ###"
pip3 install 'boto3-stubs[ec2,sqs,dynamodb,apigateway,s3,sns]' -t $DEPLOYMENT_PATH/$SHARED_RESOURCE_CATEGORY/packages/$PACKAGE/src/python/lib/python3.8/site-packages/

echo "### Download request module. ###"
pip3 install requests -t  $DEPLOYMENT_PATH/$SHARED_RESOURCE_CATEGORY/packages/$PACKAGE/src/python/lib/python3.8/site-packages/

echo "### Download pymsteams module. ###"
pip3 install pymsteams -t  $DEPLOYMENT_PATH/$SHARED_RESOURCE_CATEGORY/packages/$PACKAGE/src/python/lib/python3.8/site-packages/
