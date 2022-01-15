
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
    This program deletes the alarms for a terminated instance.
    It deletes those alarms which have instance Id as prefix in the alarm name.
    It is triggered by the EventBridge, based on instance state change
    notification events.
    '''

    try:
        instance_id: str = event['detail']['instance-id']
        state: str = event['detail']['state']

        print(
            f'Triggered by {state} state notification of instance {instance_id}')

        '''Check for alarms using the instance ID as prefix'''
        available_alarms = cloudwatch_client.describe_alarms(
            AlarmNamePrefix=f'{instance_id}',
            AlarmTypes=['CompositeAlarm', 'MetricAlarm']
        )

        composite_alarms_names: List[str] = [
            alarm['AlarmName'] for alarm in available_alarms['CompositeAlarms']
        ]

        metric_alarms_names: List[str] = [
            alarm['AlarmName'] for alarm in available_alarms['MetricAlarms']
        ]

        '''Delete the composite alarms first.'''
        if composite_alarms_names:
            cloudwatch_client.delete_alarms(
                AlarmNames=composite_alarms_names)
            print(
                f'Successfully deleted these composite alarms {composite_alarms_names}')
        else:
            print('No composite alarm to delete.')

        print('')

        '''Delete the metric alarms'''
        if metric_alarms_names:
            cloudwatch_client.delete_alarms(
                AlarmNames=metric_alarms_names)
            print(
                f'Successfully deleted these metrics alarms {metric_alarms_names}')
        else:
            print('No metric alarm to delete')

        print('')

    except Exception as err:
        print(err)
        print('Aborted! because of above error.')
        raise err
    else:
        print('Successfully executed')
        event['status_code'] = 200
        return event
