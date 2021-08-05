from os import close
import sys
import boto3
import json
from typing import Dict, Any
from datetime import datetime

user_policy: Dict[str, Any] = {
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": [
                "execute-api:*"
            ],
            "Effect": "Allow",
            "Resource": "*"
        }
    ]
}

def main(aws_profile: str, aws_region: str, deployment_id: str, tf_bucket: str, account: str, user_name: str):
    '''
    This is a pre-setup process to setup the metadata in SSM Parameter store and create an IAM user, S3 bucket to store Terraform state
    and secret having user access key and secret access key.
    '''
    LOGFILE: str = f'setup_{deployment_id}_{account}_' + \
        str(datetime.now().strftime('%Y-%m-%d_%H_%M_%S'))
    output_file:str = './logs/'+LOGFILE+'.txt'
    OUTPUT = open((output_file), 'w')
    try:
        aws_session = boto3.session.Session(profile_name=aws_profile)
        iam_client = aws_session.client('iam')
        secrets_manager_client = aws_session.client('secretsmanager', region_name=aws_region)
        s3_client = aws_session.client('s3', region_name=aws_region)
        ssm_client  =aws_session.client('ssm',region_name=aws_region)

        
        # Step 1. Create IAM user.
        try:
            iam_client.get_user(UserName=user_name)
        except Exception as err:
            iam_client.create_user(
                UserName=user_name
            )
            iam_client.put_user_policy(
                UserName=user_name,
                PolicyDocument=json.dumps(user_policy),
                PolicyName='AllowAccessToExecuteApi'
            )
            print(f'Created user {user_name}.',file=OUTPUT)
        else:
            print(f'No need to create user {user_name} as it already exists.',file=OUTPUT)

        create_access_key_response: Dict[str, Any] = {}
        
        create_access_key_response = iam_client.create_access_key(
            UserName=user_name
        )
        access_key: str = create_access_key_response['AccessKey']['AccessKeyId']
        secret_access_key: str = create_access_key_response['AccessKey']['SecretAccessKey']

        # Step 2. Create secret.
        secret_name:str = f'/rift/{deployment_id}/user/credentials'
        try:
            secrets_manager_client.describe_secret(
                SecretId=secret_name
            )
            secrets_manager_client.update_secret(
                SecretId=secret_name,
                SecretString=json.dumps({
                    "access_key": access_key,
                    "secret_key": secret_access_key
                })
            )
            print(f'Updated secret /{deployment_id}/user/credentials with new Access key and Secret access key.',file=OUTPUT)
        except Exception as err:
            secrets_manager_client.create_secret(
                Name=secret_name,
                SecretString=json.dumps({
                    "access_key": access_key,
                    "secret_key": secret_access_key
                })
            )
            print(f'Stored Access key and Secret access key to secret manager secret {secret_name}',file=OUTPUT)

        # Step 3. Create bucket for Terraform State.
        try:
            s3_client.head_bucket(
                Bucket=tf_bucket,
                ExpectedBucketOwner=account
            )
            print(
                f'No need to create new Terraform state bucket {tf_bucket} as it already exists.', file=OUTPUT)
        except Exception as err:
            s3_client.create_bucket(
                ACL='private',
                Bucket=tf_bucket,
                CreateBucketConfiguration={
                    'LocationConstraint': aws_region
                })
            print(
                f'Created bucket {tf_bucket} to store Terraform state.',file=OUTPUT)
        
        # Step 4. Store metadata.
        try:
            ssm_client.put_parameter(
                Name=f'/rift/{deployment_id}/deployment-id',
                Description='Deployment Id.',
                Value=deployment_id,
                Type='String',
                Overwrite=True
            )
            ssm_client.put_parameter(
                Name=f'/rift/{deployment_id}/tf-state-bucket',
                Description='Terraform State bucket name.',
                Value=tf_bucket,
                Type='String',
                Overwrite=True
            )
            print(f'Stored deployment id and TF state bucket name in ssm parameter store.',file=OUTPUT)
            print(f'/rift/{deployment_id}/deployment-id={deployment_id}', file=OUTPUT)
            print(f'/rift/{deployment_id}/tf-state-bucket={tf_bucket}', file=OUTPUT)
        except Exception as err:
            print(err,file=OUTPUT)
            print('Failed to store metadata in SSM paramter store.',file=OUTPUT)

    except Exception as err:
        print(err,file=OUTPUT)
        print(f'Failed to complete the pre deployment setup.',file=OUTPUT)
        print(1) # Return 1 to the setup script to abort.
    else:
        print(f'TF state bucket: {tf_bucket}',file=OUTPUT)
        print(output_file)
    finally:
        print(f'Deployment Id: {deployment_id}',file=OUTPUT)
        print(f'AWS account: {account}', file=OUTPUT)
        OUTPUT.close()


if __name__ == '__main__':
    main(sys.argv[1],  # profile
         sys.argv[2],  # region
         sys.argv[3],  # deployment id
         sys.argv[4],  # tf bucket
         sys.argv[5],  # aws account
         sys.argv[6])  # user
