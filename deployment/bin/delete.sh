#!/bin/bash +xe
# Use this script to delete the resources.
#Declare variables
readonly RESOURCES_PATH="../../deployment/terraform/"
RESULT=0
echo -e 
echo -e "\033[1m The delete process does not automatically remove the IAM user and S3 bucket.\033[0m"
echo -e "\033[1m Refer \033[96mREADME.md\033[0m \033[1mfor details about the process.\033[32m[Recommended]\033[0m"
# Declare functions.
# Provide the AWS configration to authenticate to the account.
function input {

    echo -e "\033[1mEnter AWS local profile name \033[0m\033[96m[default]:\033[0m "
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
        echo -e "\033[1mEnter AWS region:\033[0m"
        read REGION
        aws sts get-caller-identity --profile $PROFILE --region $REGION > /dev/null
        if [[ $? -ne 0 ]]
        then 
            echo -e "\033[1mInvalid region \033[0m\033[96m$REGION\033[0m"
            exit 1
        fi
    fi
    set -e
    echo -e "\033[1mEnter the deployment Id:\033[0m"
    read DEPLOYMENT_ID
    AWS_ACCOUNT_NUMBER=$(aws sts get-caller-identity --output text --query Account --profile $PROFILE)
    RESULT=$(python3 utils/delete.py $PROFILE $REGION $DEPLOYMENT_ID $AWS_ACCOUNT_NUMBER)
    if [[ $RESULT == 1 ]]
    then 
        echo -e "\033[1mCould not retrieve the Terraform state bucket for deployment \033[0m\033[96m$DEPLOYMENT_ID.\033[0m"
        echo -e "\033[1mEnter complete name of S3 bucket which has terraform state for the deployment \033[0m\033[96m$DEPLOYMENT_ID:\033[0m" 
        read TERRAFORM_STATE_BUCKET
    else
        TERRAFORM_STATE_BUCKET=$RESULT
    fi
}

# Execute Terraform to destroy the resources.
function destroy {
    
    cd $RESOURCES_PATH
    rm -rf .terraform
    rm -rf .terraform.lock.hcl
    terraform init --backend-config="bucket=$TERRAFORM_STATE_BUCKET" \
    --backend-config="key=riFT/terraform_state.tfstate" \
    --backend-config="region=$REGION" \
    --backend-config="profile=$PROFILE" 
    terraform destroy \
    --var=aws-profile=$PROFILE \
    --var=aws-region=$REGION \
    --var=deployment-id=$DEPLOYMENT_ID
    
}

# Confirm.
function confirm_and_execute {
    echo ""
    echo -e "\033[1mAWS account: \033[0m\033[96m$AWS_ACCOUNT_NUMBER\033[0m"
    echo -e "\033[1mTerraform bucket: \033[0m\033[96m$TERRAFORM_STATE_BUCKET\033[0m"
    echo -e "\033[1mRemove all resources of deployment: \033[0m\033[96m$DEPLOYMENT_ID\033[0m"
    echo -e "\033[1mPlease confirm. \033[0m\033[96m[y/n]\033[0m"
    read CONFIRM
    if [[ $CONFIRM == 'y' ]] || [[ $CONFIRM == 'Y' ]]
    then 
        destroy
    fi
}

input
confirm_and_execute

if [ $? == 0 ]
then
    echo -e "\033[1mSuccessfully removed deployment: \033[0m\033[96m$DEPLOYMENT_ID\033[0m"
    echo -e "\033[1mAWS account: \033[0m\033[96m$AWS_ACCOUNT_NUMBER\033[0m"
    echo -e "\033[1mTF state bucket: \033[0m\033[96m$TERRAFORM_STATE_BUCKET\033[0m"
else
    exit 1
fi