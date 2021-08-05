import boto3
import sys
from datetime import datetime
from typing import Dict, Any

def main(aws_profile: str, aws_region: str,deployment_id: str, account: str):
    '''
    This is pre-delete step. It uses the deployment Id to fetch the Terraform state bucket from the SSM Parameter store 
    and pass it to the Terraform.
    '''
    
    LOGFILE: str = f'delete_{deployment_id}_{account}_' + \
        str(datetime.now().strftime('%Y-%m-%d_%H_%M_%S'))
    output_file:str = './logs/'+LOGFILE+'.txt'
    OUTPUT = open((output_file), 'w')
    try:
        aws_session = boto3.session.Session(profile_name=aws_profile)
        s3_client = aws_session.client('s3', region_name=aws_region)
        ssm_client  =aws_session.client('ssm',region_name=aws_region)

        ssm_response: Dict[str,Any] = {}
        # Get the name of the Terraform state bucket for the given deployment id.
        ssm_response = ssm_client.get_parameter(
            Name=f'/rift/{deployment_id}/tf-state-bucket'
        )
        tf_bucket: str = None
        tf_bucket = ssm_response['Parameter']['Value']
        s3_client.head_bucket(
                Bucket=tf_bucket,
                ExpectedBucketOwner=account
            )
        

    except Exception as err:
        print(err,file=OUTPUT)
        print(f'Failed to retrive the SSM parameter /rift/{deployment_id}/tf-state-bucket',file=OUTPUT)
        print(1)  # Return 1 to the delete script to abort.
    else:
        print(f'TF state bucket: {tf_bucket}',file=OUTPUT)
        print(tf_bucket) # Return TF bucket name to the delete script.
    finally:
        print(f'Deployment Id: {deployment_id}',file=OUTPUT)
        print(f'AWS account: {account}', file=OUTPUT)
        OUTPUT.close()

if __name__=='__main__':
    main(sys.argv[1], # aws profile
         sys.argv[2], # aws region
         sys.argv[3], # deployment id
         sys.argv[4]) # account

