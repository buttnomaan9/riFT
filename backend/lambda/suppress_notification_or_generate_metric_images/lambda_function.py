import boto3
import os
import json
from botocore.exceptions import ClientError
from typing import Dict, Any
from pprint import pprint
from datetime import datetime
from dateutil import tz
from botocore.config import Config
from util.presignedurl_util import generate_presigned_url
from util.create_metric_image_util import create_metric_images_urls

custom_boto3_config = Config(
   retries = {
      'max_attempts': 10,
      'mode': 'standard'
   }
)
to_zone = tz.tzlocal()
aws_region: str = os.environ.get('AWS_REGION')
process_metric_name: Dict[str, str] = {'Windows': 'procstat cpu_usage',
                                       'Linux': 'procstat_cpu_usage'}

aws_services: Dict[str, Any] = {
    'ec2_resource': boto3.resource('ec2', config=custom_boto3_config)
}

aws_services['sns_client'] = boto3.client('sns',config=custom_boto3_config)
aws_services['eventbridge_client'] = boto3.client('events',config=custom_boto3_config)
aws_services['ec2_client'] = boto3.client('ec2',config=custom_boto3_config)
aws_services['secretsmanager_client'] = boto3.client('secretsmanager',config=custom_boto3_config)
aws_services['cloudwatch_client'] = boto3.client('cloudwatch',config=custom_boto3_config)
aws_services['s3_resource'] = boto3.resource('s3',config=custom_boto3_config)
aws_services['cloudwatch_resource'] = boto3.resource('cloudwatch',config=custom_boto3_config)


def lambda_handler(event, context):
    '''
    This lambda generates metric images of the alarm current state. It first checks if an instance is tagged to suppress cpu credit alarm.
    Event is not triggered if the instance is tagged as SuppressCpuCreditAlarm=True or SuppressCpuCreditAlarm=true.
    '''
    response: Dict[str, Any] = {}
    try:

        out_event: Dict[str, Any] = {}
        message: str = event['Records'][0]['Sns']['Message']
        # Need to do this as Sns Message is a str not Dict.
        alarm_details: Dict[str:Any] = json.loads(message)
        out_event['alarm-details'] = alarm_details
        out_event['subject'] = event['Records'][0]['Sns']['Subject']
        alarm_name: str = alarm_details['AlarmName']
        instance_id: str = alarm_name[:19]
        suppress_alarm: str = 'False'
        app: str = ''
        instance = aws_services['ec2_resource'].Instance(instance_id)
        instance_type: str = instance.instance_type
        out_event['instance-type'] = instance_type
        image = instance.image
        platform: str = 'Linux' if 'linux' in image.platform_details.lower() else 'Windows'
        out_event['platform'] = platform
        for tag in instance.tags:
            if tag['Key'] == os.environ.get('SUPPRESS_TAG_NAME'):
                suppress_alarm = tag['Value']
            if tag['Key'] == 'Name':
                app = tag['Value']
        out_event['app'] = app
        if suppress_alarm.lower() == 'true':
            print(
                f'Suppressed alarm {alarm_name} for instance {instance_id} of application {app}.')
        else:
            print(f'Do not suppress alarm {alarm_name}.')
            metric_images_urls: Dict[str, str] = create_metric_images_urls(alarm_details, [
                'CPUUtilization', 'CPUCreditBalance', process_metric_name[platform]], aws_services, instance_type)
            print('Successfully generated the images.')
            suppress_api_url: str = generate_presigned_url(
                aws_services['secretsmanager_client'], instance_id)

            print(f'Generated suppressed api url. \n {suppress_api_url}')
            out_event['metric-images-urls'] = metric_images_urls
            out_event['suppress-api-url'] = suppress_api_url

    except (Exception, ClientError) as err:
        print(err)
        print('Aborted! because of above error.')
        return err
    else:
        print('Successfully executed.')
        return out_event
    finally:
        '''
        The event trigger logic is put in finally block to ensure to trigger down stream functions even if the image generation fails.
        Trigger event if the alarm is not suppressed. 
        '''
        response=None
        if suppress_alarm.lower() != 'true':
            out_event['function-name'] = [context.function_name]
            out_event['function-outcome'] = [os.environ.get('FN_OUTCOME')]
            complete_out_event: Dict[str, Any] = {
                'Source': "lambda.amazonaws.com",
                'DetailType': os.environ.get('NOTIFICATION_FROM_FN'),
                'Detail': json.dumps(out_event),
                'EventBusName': os.environ.get('DYNAMIC_EC2_MONITOR_EVENT_BUS_NAME')
            }
            print(complete_out_event)
            response = aws_services['eventbridge_client'].put_events(
                Entries=[complete_out_event]
            )
        print(response)
