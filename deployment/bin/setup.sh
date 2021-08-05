#!/bin/bash +xe
# This script deploys the resources.
echo ""
echo -e "----------------------------------------------\033[1m\033[96mPREREQUISITES\033[0m-----------------------------------------------"
echo -e "\033[1m 1. An IAM user to create pre-signed API url."
echo -e "\033[1m You can choose to provide an existing user when prompted or let the deployment process create a user." 
echo -e " Refer \033[96mREADME.md\033[0m \033[1mfor details about the process.\033[32m[Recommended]\033[0m"
echo  ""  
# Declare variables.
readonly RESOURCES_PATH="../../deployment/terraform/"
readonly SCRIPT_PATH=$(pwd)
METADATA_FILE=0
readonly SUFFIX=$(od -x /dev/urandom | head -1 | awk '{OFS=""; print $2,$3,$4}')
readonly USER_PREFIX="rift-api-gateway-user"
# Declare functions.
# Provide the AWS configration to authenticate to the account.
function take_input {
    
    echo -e "\033[1mEnter AWS local profile name \033[0m\033[96m[default]: \033[0m"
    read PROFILE
    if [[ $PROFILE == '' ]]
    then
        PROFILE="default" 
    fi
    aws sts get-caller-identity --profile $PROFILE > /dev/null
    if [[ $? -ne 0 ]]
    then
        exit 1
    fi
    REGION=$(aws configure get region --profile $PROFILE) 
    if [[ -z $REGION ]]
    then
        echo -e "\033[1mEnter AWS region: \033[0m"
        read REGION
        aws sts get-caller-identity --profile $PROFILE --region $REGION > /dev/null
        if [[ $? -ne 0 ]]
        then 
            echo -e "\033[1mInvalid region \033[0m\033[96m$REGION\033[0m"
            exit 1
        fi
    fi
    set -e
    echo -e "\033[1mEnter a name for the deployment to identify resources in the account \033[0m\033[96m[$SUFFIX]:\033[0m"
    read DEPLOYMENT_ID
    if [[ $DEPLOYMENT_ID == '' ]]
    then
        DEPLOYMENT_ID=$SUFFIX
    fi
    BUCKET_SUFFIX=$DEPLOYMENT_ID
    echo -e "\033[1mEnter IAM user name \033[0m\033[96m[$USER_PREFIX-$DEPLOYMENT_ID]:\033[0m"
    read USER
    if [[ $USER == '' ]]
    then
        USER="$USER_PREFIX-$DEPLOYMENT_ID"
    fi
    readonly AWS_ACCOUNT_NUMBER=$(aws sts get-caller-identity --output text --query Account --profile $PROFILE)
    readonly TERRAFORM_STATE_BUCKET="rift-tf-state-bucket-"$BUCKET_SUFFIX
}

# Set up tf bucket and user.
function configure {
    METADATA_FILE=$(python3 utils/setup.py $PROFILE $REGION $DEPLOYMENT_ID $TERRAFORM_STATE_BUCKET $AWS_ACCOUNT_NUMBER $USER)
}

# Execute Terraform to deploy the resources.
function deploy {
   
    cd $RESOURCES_PATH
    rm -rf .terraform
    rm -rf .terraform.lock.hcl
    terraform init --backend-config="bucket=$TERRAFORM_STATE_BUCKET" \
    --backend-config="key=riFT/terraform_state.tfstate" \
    --backend-config="region=$REGION" \
    --backend-config="profile=$PROFILE" 
    terraform apply \
    --var=aws-profile=$PROFILE \
    --var=aws-region=$REGION \
    --var=deployment-id=$DEPLOYMENT_ID
    
}

# Deploy lambda layer.
function package_binaries {
    ./package_lambda_layers.sh
}

# Confirm.
function confirm_and_execute {
    echo ""
    echo -e "\033[1mAWS profile: \033[0m\033[96m$PROFILE\033[0m"
    echo -e "\033[1mAWS region: \033[0m\033[96m $REGION \033[0m"
    echo -e "\033[1mAWS account: \033[0m\033[96m$AWS_ACCOUNT_NUMBER\033[0m"
    echo -e "\033[1mDeployment Id: \033[0m\033[96m$DEPLOYMENT_ID\033[0m"
    echo -e "\033[1mIAM user: \033[0m\033[96m$USER\033[0m"
    echo -e "\033[1mS3 bucket to store Terraform state: \033[0m\033[96m$TERRAFORM_STATE_BUCKET\033[0m"
    echo -e "\033[1mPlease confirm to begin set up. \033[0m\033[96m[y/n]: \033[0m"
    read CONFIRM
    if [[ $CONFIRM == 'y' ]] || [[ $CONFIRM == 'Y' ]]
    then 
        configure
        if [[ $METADATA_FILE == 1 ]]
        then
            echo -e "\033[1mAborted deployment \033[0m\033[96m$DEPLOYMENT_ID.\033[0m"
            echo -e "Check logs for details."
            exit 1
        else
            package_binaries
            deploy
            cd $SCRIPT_PATH
        fi
    else
        exit 1
    fi
}

take_input
confirm_and_execute

if [[ $? == 0 ]]
then
    SNS_TOPIC="receive-ec2-notifications-$DEPLOYMENT_ID"
    echo -e "\033[1mSuccessfully deployed riFT to \033[0m\033[96m$AWS_ACCOUNT_NUMBER\033[0m"
    echo -e "\033[1mDeployment Id: \033[0m\033[96m$DEPLOYMENT_ID\033[0m"
    echo -e "\033[1mTf state bucket: \033[0m\033[96m$TERRAFORM_STATE_BUCKET\033[0m"
    echo -e "\033[1mSave metadata file \033[32m[Recommended]\033[0m: \033[0m\033[96m$METADATA_FILE\033[0m"
    echo -e "\033[1mYou will need the deployment Id to delete the resources.\033[0m"
    echo -e "\033[1mSubscribe to SNS topic \033[0m\033[96m$SNS_TOPIC\033[0m\033[1m to receive notifications of alarms in email.\033[0m"
    echo "Subscribers SNS topic: $SNS_TOPIC" >> $METADATA_FILE
else
    exit 1
fi
