import boto3
from typing import Any, Dict
from botocore import config
from botocore.exceptions import ClientError
import os
import json
from botocore.config import Config
custom_boto3_config = Config(
   retries = {
      'max_attempts': 10,
      'mode': 'standard'
   }
)
ec2_resource = boto3.resource('ec2',config=custom_boto3_config)


def lambda_handler(event, context):
    '''This program tags an instance to suppress the notifications of alarms.'''
    aws_region: str = os.environ.get('AWS_REGION')
    suppress_tag_name: str = os.environ.get('SUPPRESS_TAG_NAME')
    suppress_tag_value: str = os.environ.get('SUPPRESS_TAG_VALUE')

    response_html: str = ''
    try:
        print(f'event is {event}')
        instance_id: str = event['instance-id']
        print(f'Suppress CPU credit balance alarm of {instance_id}')
        instance = ec2_resource.Instance(instance_id)
        print(f'suppress_tag_name={suppress_tag_name}')
        instance.create_tags(
            Tags=[
                {
                    'Key': suppress_tag_name,
                    'Value': suppress_tag_value
                },
            ])
        console_url_instance: str = f'https://{aws_region}.console.aws.amazon.com/ec2/v2/home?region={aws_region}#Instances:search={instance_id};sort=instanceId'
        message: str = f'Successfully suppressed the notifications for the alarm. \
                         To enable the notifications, remove this tag {suppress_tag_name}={suppress_tag_value} from instance <a href={console_url_instance}>{instance_id}</a>'
    except (Exception, ClientError) as err:
        print(err)
        raise err
    else:
        
        response_html = f'<html> \
                                             <head> \
                                             <style> \
                                             p \
                                             {{ \
                                                 background-color:floralwhite; \
                                                 font-family:Cambria, Cochin, Georgia, Times, Times New Roman, serif \
                                             }} \
                                             </style> \
                                             </ head> \
                                             <body> \
                                             <p>{message}</p> \
                                             </ body> \
                                             </ html>'
        print(response_html)
        return response_html
