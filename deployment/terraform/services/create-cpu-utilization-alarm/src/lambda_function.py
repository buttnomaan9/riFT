import boto3
import os
import json
from typing import List, Dict, Any
from botocore.config import Config
from dataclasses import dataclass

custom_boto3_config = Config(
    retries={
        'max_attempts': 10,
        'mode': 'standard'
    }
)

ec2_resource = boto3.resource('ec2', config=custom_boto3_config)
cloudwatch_client = boto3.client('cloudwatch', config=custom_boto3_config)
event_bridge = boto3.client('events', config=custom_boto3_config)
ssm_client  = boto3.client('ssm',config=custom_boto3_config)

baseline_cpu_utilization: Dict[str, float] = {
    't2.nano': 5,
    't2.micro': 10,
    't2.small': 20,
    't2.medium': 20,
    't2.large': 30,
    't2.xlarge': 22.5,
    't2.2xlarge': 17,
    't3.nano': 5,
    't3.micro': 10,
    't3.small': 20,
    't3.medium': 20,
    't3.large': 30,
    't3.xlarge': 40,
    't3.2xlarge': 40,
    't3a.nano': 5,
    't3a.micro': 10,
    't3a.small': 20,
    't3a.medium': 20,
    't3a.large': 30,
    't3a.xlarge': 40,
    't3a.2xlarge': 40
}

@dataclass
class AlarmConfigurationParams:
    threshold: str
    period: str
    datapoints: str
    evaluation_periods: str

def lambda_handler(event, context):
    '''
    This lambda program creates cpu utilization alarm for instance of T class.
    It is triggered from the EventBridge, based on instance state change
    notification events.
    Metric period,datapoints and evaluation period 
    are provided as input.
    The alarm is created using per vCPU core baseline utilization.
    '''

    out_event: Dict[str, Any] = {}

    compute_intensive_workloads_regix_list: List[str] = []
    compute_intensive_workloads_regix_env: str = os.environ.get(
        'COMPUTE_INTENSIVE_WORKLOADS_REGIX_LIST')
    if compute_intensive_workloads_regix_env is not None:
        compute_intensive_workloads_regix_list = compute_intensive_workloads_regix_env.split(
            ',')
    try:
        instance_id: str = event['detail']['instance-id']
        out_event['instance-id'] = instance_id
        cpu_credit_alarm_name: str = event['detail']['cpu-credit-alarm-name']
        out_event['cpu-credit-alarm-name'] = cpu_credit_alarm_name

        instance = ec2_resource.Instance(instance_id)
        instance_type = instance.instance_type
        print(f'Instance type is {instance_type}')

        # Get the alarm configration data from ssm parameter store.
        config:AlarmConfigurationParams = get_configuration_data(instance_type)

        print('Running for below arguments.')
        print(f'period={config.period} datapoints={config.datapoints} evaluation_periods={config.evaluation_periods}')
        print(f'Threshold used is {config.threshold}')

        '''Get the tags to name the alarm'''
        tags: List[Dict[str, str]] = instance.tags
        name: str = ''
        alarm_name: str = ''
        try:
            for tag in tags:
                if tag['Key'] == 'Name':
                    name = tag['Value']
                    break
        except Exception as err:
            print(err)
            print(f'{instance_id} does not have a Name tag.')
            name = ''
        else:
            '''Check if the application is compute intensive'''
            for regix in compute_intensive_workloads_regix_list:
                if regix in name:
                    config.datapoints = os.environ.get('ADDITIONAL_DATAPOINTS')
                    config.evaluation_periods = os.environ.get(
                        'ADDITIONAL_EVALUATION_PERIODS')

        alarm_name = '{}-{}-CPUUtilization-More-Than-Baseline-Percentage'.format(
            instance_id, instance_type)

        put_cpu_utilization_alarm_for_below_th(alarm_name,
                                               instance_id,
                                               instance_type,
                                               float(config.threshold),
                                               int(config.period),
                                               int(config.datapoints),
                                               int(config.evaluation_periods))

    except Exception as err:
        print(err)
        print('Aborted! because of above error.')
        raise err
    else:
        print('Successfully completed')
        out_event['cpu-utilization-alarm-name'] = alarm_name
        out_event['app'] = name
        out_event['instance-type'] = instance_type
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
        return out_event


'''This function creates or updates a CPUUtilization alarm.
If the alarm does not exist a new alarm is created or else existing alarm is updated'''


def put_cpu_utilization_alarm_for_below_th(alarm_name: str,
                                           instance_id: str,
                                           instance_type: str,
                                           threshold: float,
                                           period: int,
                                           datapoints: int,
                                           evaluation_periods: int):

    desc: str = 'Raise alarm when CPUUtilization is above baseline utlization of instance type {}: {}'.format(
        instance_type, threshold)

    try:
        api_response = cloudwatch_client.put_metric_alarm(
            AlarmName=alarm_name,
            AlarmDescription=desc,
            ActionsEnabled=True,
            MetricName='CPUUtilization',
            Namespace='AWS/EC2',
            Dimensions=[
                {
                    'Name': 'InstanceId',
                    'Value': instance_id
                }
            ],
            Statistic='Maximum',
            Period=period,
            Threshold=threshold,
            ComparisonOperator='GreaterThanOrEqualToThreshold',
            EvaluationPeriods=evaluation_periods,
            DatapointsToAlarm=datapoints,
            # AlarmActions=alarm_action,
            Tags=[
                {
                    'Key': 'App',
                    'Value': 'AutomatedAndDynamicAlarmForCPUCredits'
                },
            ]
        )
        print(f'Response:{api_response}')
    except Exception as err:
        print(err)
        print(f'Failed {alarm_name} because of above error')
    else:
        if api_response['ResponseMetadata']['HTTPStatusCode'] == 200:
            print(f'Successfully created/updated alarm {alarm_name}')

# Get alarm bases config values.
def get_configuration_data(instance_type):
    try:
        '''Use per vCPU core utilization as baseline for CPU alarm'''
        threshold = baseline_cpu_utilization[instance_type]

        get_period:Dict[str,Any] = ssm_client.get_parameter(Name=os.environ.get('PERIOD'))
        period = get_period['Parameter']['Value']

        get_datapoints:Dict[str,Any] = ssm_client.get_parameter(Name=os.environ.get('DATAPOINTS'))
        datapoints = get_datapoints['Parameter']['Value']

        get_evaluation_periods:Dict[str,Any] = ssm_client.get_parameter(Name=os.environ.get('EVALUATION_PERIODS'))
        evaluation_periods = get_evaluation_periods['Parameter']['Value']
    except Exception as err:
        print(err)
        raise err
    else:
        return AlarmConfigurationParams(threshold,period,datapoints,evaluation_periods)
