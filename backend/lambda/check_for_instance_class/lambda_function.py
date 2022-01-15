import boto3
import os
import json
from typing import List, Dict, Any
from pprint import pprint
from botocore.config import Config

custom_boto3_config = Config(
   retries = {
      'max_attempts': 10,
      'mode': 'standard'
   }
)
ec2_resource = boto3.resource('ec2',config=custom_boto3_config)
event_bridge = boto3.client('events',config=custom_boto3_config)

def lambda_handler(event, context) -> Dict[str, Any]:
    '''The program checks for the instance class and triggers event to create alarms if the instance is of burstable type.'''

    out_event: Dict[str, Any] = {}
    try:
        instance_id: str = event['detail']['instance-id']
        state: str = event['detail']['state']
        out_event['instance-id'] = instance_id
        print(
            f'Triggered by {state} state notification of instance {instance_id}')
        instance = ec2_resource.Instance(instance_id)
        instance_type: str = instance.instance_type
        first_character_of_instane_type = instance_type[0]
        if first_character_of_instane_type != 't':
            print(
                f'Do not create CPUCreditBalance alarm as instance {instance_id} is of type {instance_type}')
        else:
            out_event['function-name'] = [context.function_name]
            out_event['function-outcome'] = [os.environ.get('FN_OUTCOME')]
            complete_out_event:Dict[str,Any] = {
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

        print(f'{instance_type}')
        first_two_character_of_type: str = instance_type[:2]

        print(f'Instance class: {first_two_character_of_type}')
       
    except Exception as err:
        print(err)
        print('Aborted! because of above error.')
        raise err
    else:
        print('Successfully completed')
        pprint(out_event, indent=4)
        return out_event
