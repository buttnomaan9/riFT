import boto3
import os
import json
import sys
from typing import Dict, Any
from datetime import datetime


def main(aws_profile: str,
         aws_region: str,
         deployment_id: str,
         account: str,
         operation: str,
         period: int = 0,
         datapoints: int = 0,
         evaluation_periods: int = 0):
    '''
    This function pushes create or update alarm notifcations to the maintenance SNS topic to update or create alarms for existing burstable instances.
    The SNS topic invokes lambda function which puts events to the EventBridge bus to trigger various create-alarm functions.
    It takes operation type as input with value as 'create' to put alarms for existing instance and 'update' as input to modify config of alarms. 
    '''
    try:
        
        LOGFILE: str = f'{operation}_{deployment_id}_{account}_' + \
            str(datetime.now().strftime('%Y-%m-%d_%H_%M_%S'))
        output_file: str = './logs/'+LOGFILE+'.txt'
        OUTPUT = open((output_file), 'w')
        aws_session = boto3.session.Session(profile_name=aws_profile)
        sns_client = aws_session.client('sns', region_name=aws_region)
        ssm_client = aws_session.client('ssm', region_name=aws_region)
        # Step 1. Update the alarm configuration SSM parameters with new values.
        # Do not do if the operation type is create.
        if (operation == 'update'):
            # update for only non zero values.
            if (period !=0 and datapoints !=0  and evaluation_periods !=0):
                try:
                    ssm_client.put_parameter(
                        Name=f'/rift/{deployment_id}/config/alarms/period',
                        Description='Period',
                        Value=period,
                        Type='String',
                        Overwrite=True
                    )
                    ssm_client.put_parameter(
                        Name=f'/rift/{deployment_id}/config/alarms/datapoints',
                        Description='Period',
                        Value=datapoints,
                        Type='String',
                        Overwrite=True
                    )
                    ssm_client.put_parameter(
                        Name=f'/rift/{deployment_id}/config/alarms/evaluation-periods',
                        Description='Period',
                        Value=evaluation_periods,
                        Type='String',
                        Overwrite=True
                    )
                    
                    print(f'New value for Period={period}, Datapoints={datapoints}, Evaluation Periods={evaluation_periods}',file=OUTPUT)

                except Exception as err:
                    print(err, file=OUTPUT)
                    print(
                        f'Provide non zero values for Period, Datapoints and Evaluation periods.', file=OUTPUT)
                    raise err

        # Step 2. Get the maintenance topic arn using the metadata.
        get_maintenance_topic_ssm_response: Dict[str, Any] = ssm_client.get_parameter(
            Name=f'/rift/{deployment_id}/sns/topic/maintenance'
        )
        maintenance_topic_arn: str = get_maintenance_topic_ssm_response['Parameter']['Value']
        print(f'{operation} alarms of deployment {deployment_id}.', file=OUTPUT)
       
        # Step 3. Publish the notification.
        response = sns_client.publish(
            TopicArn=maintenance_topic_arn,
            Message=json.dumps({'OPERATION_TYPE': operation}),
            Subject=operation+' alarms',
            MessageStructure='String'
        )
        print(
            f'Published notification to maintenance topic {maintenance_topic_arn}', file=OUTPUT)
        print(response,file=OUTPUT)
    except Exception as err:
        print(err, file=OUTPUT)
        print(1)  # Pass non zero value to abort the calling script.
    else:
        print(0)  # Pass 0 for success.


if __name__ == '__main__':
    main(sys.argv[1]  # profile
         , sys.argv[2]  # region
         , sys.argv[3]  # deployment id
         , sys.argv[4]  # account
         , sys.argv[5]  # operation type [update or create]
         , sys.argv[6]  # alarm period
         , sys.argv[7]  # alarm datapoints
         , sys.argv[8])  # alarm evaluation periods
