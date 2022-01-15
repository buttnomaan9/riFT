import boto3
import os
from typing import List, Dict, Any
from pprint import pprint
from botocore.config import Config

custom_boto3_config = Config(
    retries={
        'max_attempts': 10,
        'mode': 'standard'
    }
)

cloudwatch_client = boto3.client('cloudwatch', config=custom_boto3_config)


def lambda_handler(event, context):
    '''
    This program creates a composite alarm. It needs the names of the child alarms, instance ID, instance type and name of the application
    It is triggered from EventBridge.
    '''

    try:
        instance_id: str = event['detail']['instance-id']
        instance_type: str = event['detail']['instance-type']
        cpu_credit_alarm_name = event['detail']['cpu-credit-alarm-name']
        cpu_utilization_alarm_name = event['detail']['cpu-utilization-alarm-name']
        app: str = event['detail']['app']
        action = os.environ.get('ACTION')
        print(f'Action={action}')
        action: str = [os.environ.get('ACTION')]

        print(
            f'Create composite alarm for {cpu_credit_alarm_name} and {cpu_utilization_alarm_name}')

        desc: str = f'Composite alarm for {cpu_credit_alarm_name} and {cpu_utilization_alarm_name}'
        alarm_name: str = f'{instance_id}-{instance_type}-Composite-Alarm-CPUCreditBalance-And-CPUUtilization-Thresholds-Breached'
        alarm_created_response = cloudwatch_client.put_composite_alarm(
            ActionsEnabled=True,
            AlarmActions=action,
            AlarmDescription=desc,
            AlarmName=alarm_name,
            AlarmRule=f'ALARM({cpu_credit_alarm_name}) AND ALARM({cpu_utilization_alarm_name})',
            Tags=[
                {
                    'Key': 'App',
                    'Value': 'AutomatedAndDynamicAlarmForCPUCredits'
                },
            ]
        )

        print(f'{alarm_created_response}')

        print(
            f'Created composite alarm {alarm_name} for instance {instance_id} of application {app}')

    except Exception as err:
        print(err)
        print('Aborted! because of above error.')
        raise err
    else:
        print('Successfully executed')
        event['status_code'] = 200
        return event
