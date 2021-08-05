#!/bin/bash +xe
# This script create alarms or update the configuration of alarms.
# Input AWS profile to use.
echo ""
echo -e "\033[96mThis script updates the existing alarm(s) Period, number of Datapoints and Evaluation Periods." 
echo -e "It can also create alarms for existing instance(s).\033[0m"
PERIOD=0
DATAPOINTS=0
EVALUATION_PERIODS=0
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
            echo -e "\033[1mInvalid region. \033[0m\033[96m$REGION\033[0m"
            exit 1
        fi
    fi
    set -e
    echo -e "\033[1mDo you want to?: "
    echo -e "\033[96m1.\033[0m \033[1mUpdate configuration of existing alarms."
    echo -e "\033[96m2.\033[0m \033[1mCreate alarms for existing instances.\033[0m"
    read SELECTION
    if [[ $SELECTION == '1' ]]
    then
        ACTION="update" 
        input_new_configuration
    elif [[ $SELECTION == '2' ]]
    then 
        ACTION="create"
    else 
        echo -e "\033[1mInvalid selection. \033[96m$SELECTION\033[0m"
        exit 1
    fi
    echo -e "\033[1mEnter the deployment Id:\033[0m"
    read DEPLOYMENT_ID
    if [[ $DEPLOYMENT_ID == '' ]]
    then
        echo -e "\033[1mDeployment Id is required.\033[0m"
        exit 1
    fi
    readonly AWS_ACCOUNT_NUMBER=$(aws sts get-caller-identity --output text --query Account --profile $PROFILE)

}


# Confirm.
function confirm_and_execute {
    echo ""
    echo -e "\033[1mAWS profile: \033[0m\033[96m$PROFILE\033[0m"
    echo -e "\033[1mAWS region: \033[0m\033[96m $REGION \033[0m"
    echo -e "\033[1mAWS account: \033[0m\033[96m$AWS_ACCOUNT_NUMBER\033[0m"
    echo -e "\033[1mDeployment Id: \033[0m\033[96m$DEPLOYMENT_ID\033[0m"
    echo -e "\033[1mPlease confirm to $ACTION alarms config. \033[0m\033[96m[y/n]: \033[0m"
    read CONFIRM
    if [[ $CONFIRM == 'y' ]] || [[ $CONFIRM == 'Y' ]]
    then 
        maintenance
        if [[ $RESULT == 1 ]]
        then
            echo -e "\033[1mAborted $ACTION alarm action for deployment \033[0m\033[96m$DEPLOYMENT_ID.\033[0m"
            echo -e "Check logs for details."
            exit 1
        elif [[ $RESULT == 0 ]]
        then
            echo -e "\033[1mSuccessfully published $ACTION alarm action for deployment \033[0m\033[96m$DEPLOYMENT_ID.\033[0m"
        fi
    else
        exit 1
    fi
}

function maintenance {
    RESULT=$(python3 utils/maintenance.py $PROFILE $REGION $DEPLOYMENT_ID $AWS_ACCOUNT_NUMBER $ACTION $PERIOD $DATAPOINTS $EVALUATION_PERIODS)
    echo $RESULT
}

function input_new_configuration {
    echo -e "\033[1mEnter new Period in seconds: \033[0m "
    read PERIOD
    echo -e "\033[1mEnter new number of Datapoints:\033[0m "
    read DATAPOINTS
    echo -e "\033[1mEnter new number of Evaluation periods: \033[0m "
    read EVALUATION_PERIODS
}

take_input
confirm_and_execute

