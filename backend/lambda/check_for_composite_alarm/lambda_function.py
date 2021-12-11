
import boto3
import os
import json
from typing import List, Dict, Any
from pprint import pprint
from botocore import config
from botocore.config import Config
custom_boto3_config = Config(
   retries = {
      'max_attempts': 10,
      'mode': 'standard'
   }
)

ec2_resource = boto3.resource('ec2',config=custom_boto3_config)
cloudwatch_client = boto3.client('cloudwatch',config=custom_boto3_config)
event_bridge = boto3.client('events',config=custom_boto3_config)


def lambda_handler(event, context):
    '''
    This program checks if a composite alarm exists for the instance.
    It uses the Instance Id and value of Name tag to create the alarm name before looking for it.
    '''
    out_event: Dict[str, Any] = {}
    try:
        print(f'{event}')
        instance_id: str = event['detail']['instance-id']
        out_event['instance-id'] = instance_id
        app: str = ''
        instance = ec2_resource.Instance(instance_id)
        try:
            for tag in instance.tags:
                if tag['Key'] == 'Name':
                    app = tag['Value']
        except Exception as err:
            print(f'{instance_id} does not have a Name tag')
            app = ''
        instance_type: str = instance.instance_type
        print(
            f'Find composite alarm for instance {instance_id} of app {app}, having instance type as {instance_type}')

        alarm_name: str = f'{instance_id}-{instance_type}-Composite-Alarm-CPUCreditBalance-And-CPUUtilization-Thresholds-Breached'
        print(f'Alarm name to look {alarm_name}')
        existing_alarms = cloudwatch_client.describe_alarms(
            AlarmNames=[alarm_name],
            AlarmTypes=['CompositeAlarm']
        )

        print('')

        if len(existing_alarms['CompositeAlarms']) == 0:
            print(f'Alarm not found. Create an alarm.')
            out_event['function-name'] = [context.function_name]
            out_event['function-outcome'] = [os.environ.get('FN_OUTCOME')]
            complete_out_event: Dict[str, Any] = {
                'Source': "lambda.amazonaws.com",
                'DetailType': os.environ.get('NOTIFICATION_FROM_FN'),
                'Detail': json.dumps(out_event),
                'EventBusName': os.environ.get('DYNAMIC_EC2_MONITOR_EVENT_BUS_NAME')
            }
            print(complete_out_event)
            response = event_bridge.put_events(
                Entries=[complete_out_event]
            )
            print(f'{response}')
        else:
            print(f'Alarm already exists. Do not create new.')

    except Exception as err:
        print(err)
        print('Aborted! because of above error.')
        raise err
    else:
        print(f'Successfully executed')
        return out_event
