import boto3
import os
import json
from pprint import pprint
from typing import List, Dict, Any
from botocore.exceptions import ClientError
from botocore.config import Config

custom_boto3_config = Config(
    retries={
        'max_attempts': 10,
        'mode': 'standard'
    }
)
aws_services: Dict[str, Any] = {
    'ec2_resource': boto3.resource('ec2', config=custom_boto3_config)
}

aws_services['eventbridge_client'] = boto3.client(
    'events', config=custom_boto3_config)

event_detail_type: Dict[str, str] = {'update': os.environ.get('UPDATE_ALARMS_CONFIG_NOTIFICATION'),
                                     'create': os.environ.get('CREATE_ALARMS_FOR_EXISTING_INSTANCES_NOTIFICATION')}
event_detail: Dict[str, str] = {'update': os.environ.get('UPDATE_ALARMS_OPERATION_TYPE'),
                                'create': os.environ.get('CREATE_ALARMS_OPERATION_TYPE')}


def lambda_handler(event, context):
    '''The function puts events to create alarms or update configuration of existing instances.'''

    try:
        message: str = event['Records'][0]['Sns']['Message']
        # Need to do this as Sns Message is a str not Dict.
        operation_detials: Dict[str:Any] = json.loads(message)
        operation_type: str = operation_detials['OPERATION_TYPE']
        '''Find all instances in an account'''
        instances = aws_services['ec2_resource'].instances
        ec2_instances: List[Any] = instances.all()
        '''Filter all T class instances'''
        t_class_instances = ec2_instances.filter(
            Filters=[{
                'Name': 'instance-type',
                'Values': ['t2.*', 't3.*', 't3a.*']
            }, 
            {
                'Name': 'instance-state-name', 
                'Values': ['running']
            }]
        )
        out_event: Dict[str, Any] = {}
        '''Publish event for the burstable class instances only.'''
        count=0
        for instance in t_class_instances.all():
            count=+1
            instance_id: str = instance.id
            instance_type: str = instance.instance_type
            out_event['instance-id'] = instance_id
            out_event['instance-type'] = instance_type
            out_event['operation-type'] = event_detail[operation_type]
            out_event['function-name'] = [context.function_name]

            complete_out_event: Dict[str, Any] = {
                'Source': "lambda.amazonaws.com",
                'DetailType': event_detail_type[operation_type],
                'Detail': json.dumps(out_event),
                'EventBusName': os.environ.get('DYNAMIC_EC2_MONITOR_EVENT_BUS_NAME')
            }
            print(f'Published event to {operation_type} alarms.')
            print(complete_out_event)
            response = aws_services['eventbridge_client'].put_events(
                Entries=[complete_out_event]
            )
            print(response)

    except (Exception, ClientError) as err:
        print(err)
        print('Aborted! because of above error..')
    else:
        print(f'Total number of events published is {count}')
        print('Successfully completed.')
