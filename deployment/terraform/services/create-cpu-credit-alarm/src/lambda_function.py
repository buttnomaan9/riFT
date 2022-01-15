import boto3
import os
import json
from typing import List, Dict, Any
from collections import namedtuple
from botocore.config import Config
from dataclasses import dataclass
custom_boto3_config = Config(
   retries = {
      'max_attempts': 10,
      'mode': 'standard'
   }
)

ec2_resource = boto3.resource('ec2',config=custom_boto3_config)
cloudwatch_client = boto3.client('cloudwatch',config=custom_boto3_config)
event_bridge = boto3.client('events',config=custom_boto3_config)
ssm_client  = boto3.client('ssm',config=custom_boto3_config)

InstanceTypesSpecs = namedtuple(
    'InstanceTypesSpecs', ['instance_type', 'max_cpu_credit', 'vCPU_count'])

'''Credit table'''
instances_credit_table: Dict[str, InstanceTypesSpecs] = {
    't3.nano': InstanceTypesSpecs('t2.nano', 144, 2),
    't3.micro': InstanceTypesSpecs('t3.micro', 288, 2),
    't3.small': InstanceTypesSpecs('t3.small', 576, 2),
    't3.medium': InstanceTypesSpecs('t3.medium', 576, 2),
    't3.large': InstanceTypesSpecs('t3.large', 864, 2),
    't3.xlarge': InstanceTypesSpecs('t3.xlarge', 2304, 4),
    't3.2xlarge': InstanceTypesSpecs('t3.2xlarge', 4608, 8),
    't3a.nano': InstanceTypesSpecs('t3a.nano', 144, 2),
    't3a.micro': InstanceTypesSpecs('t3a.micro', 288, 2),
    't3a.small': InstanceTypesSpecs('t3a.small', 576, 2),
    't3a.medium': InstanceTypesSpecs('t3a.medium', 576, 2),
    't3a.large': InstanceTypesSpecs('t3a.large', 864, 2),
    't3a.xlarge': InstanceTypesSpecs('t3a.xlarge', 2304, 4),
    't3a.2xlarge': InstanceTypesSpecs('t3a.2xlarge', 4608, 8),
}

launch_credits: Dict[str, float] = {
    't2.nano': 30,
    't2.micro': 30,
    't2.small': 30,
    't2.medium': 60,
    't2.large': 60,
    't2.xlarge': 120,
    't2.2xlarge': 240
}

@dataclass
class AlarmConfigurationParams:
    threshold: str
    period: str
    datapoints: str
    evaluation_periods: str

def lambda_handler(event, context):
    '''This function  creates cpu credit alarms for instance of T class.
    It is triggered from the EventBridge, based on instance state change
    notification events.
    Threshold,metric period,datapoints and evaluation period 
    are provided as input. 
    The instance should have a Name tage otherwise the alarm will not be created.
    The threshold for t2 class is set to the launch credits.'''
    
    out_event: Dict[str, Any] = {}
    compute_intensive_workloads_regix_list: List[str] = []
    compute_intensive_workloads_regix_env: str = os.environ.get(
        'COMPUTE_INTENSIVE_WORKLOADS_REGIX_LIST')
    if compute_intensive_workloads_regix_env is not None:
        compute_intensive_workloads_regix_list = compute_intensive_workloads_regix_env.split(
            ',')
    # Get the alarm configration data from ssm parameter store.
    config:AlarmConfigurationParams = get_configuration_data()
    
    print('Running for below arguments.')
    print(
        f'threshold={config.threshold} period={config.period} datapoints={config.datapoints} evaluation_periods={config.evaluation_periods}')

    try:
        print(f'{event}')
        instance_id: str = event['detail']['instance-id']
        out_event['instance-id'] = instance_id
        instance = ec2_resource.Instance(instance_id)
        instance_type = instance.instance_type

        print(f'{instance_type}')
        first_two_character_of_type: str = instance_type[0:2]

        print(f'Instance class: {first_two_character_of_type}')

        if first_two_character_of_type == 't2':
            print(f'As the instance is of t2 class set threshold as the launch credit')
            config.threshold = launch_credits[instance_type]

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
            print(f'{instance_id} does not have a Name tag')
            name = ''
        else:
            '''Check if the application is compute intensive'''
            for regix in compute_intensive_workloads_regix_list:
                if regix in name:
                    print(f'regix={regix}')
                    print(f'name={name}')
                    config.datapoints = os.environ.get('ADDITIONAL_DATAPOINTS')
                    config.evaluation_periods = os.environ.get(
                        'ADDITIONAL_EVALUATION_PERIODS')

        alarm_name = '{}-{}-CPUCreditBalance-Less-Than-Threshold'.format(
            instance_id, instance_type)

        put_cpu_credit_balance_alarm_for_below_th(alarm_name,
                                                  instance_id,
                                                  instance_type,
                                                  float(config.threshold),
                                                  int(config.period),
                                                  int(config.datapoints),
                                                  int(config.evaluation_periods),
                                                  first_two_character_of_type)

    except Exception as err:
        print(err)
        print('Aborted! because of above error.')
        raise err
    else:
        print('Successfully completed')
        out_event['cpu-credit-alarm-name'] = alarm_name
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


def put_cpu_credit_balance_alarm_for_below_th(alarm_name: str,
                                              instance_id: str,
                                              instance_type: str,
                                              credits_used_per_vcpu_hour: float,
                                              period: int,
                                              datapoints: int,
                                              evaluation_periods: int,
                                              instance_class: str):
    '''This function creates or updates a CPUCreditBalance alarm.
    If the alarm does not exist a new alarm is created or else existing alarm is updated'''

    desc: str = ''
    threshold: float = 0.0
    if instance_class != 't2':
        print(f'Use given threshold value.')
        threshold = instances_credit_table[instance_type].vCPU_count * \
            credits_used_per_vcpu_hour
        _80_percent_of_max_credit: float = .8 * \
            int(instances_credit_table[instance_type].max_cpu_credit)
        _20_percent_of_max_credit: float = .2 * \
            int(instances_credit_table[instance_type].max_cpu_credit)
        if threshold > _80_percent_of_max_credit:
            threshold = _20_percent_of_max_credit
        desc = 'Raise alarm when CPUCreditBalance drops below {}'.format(
            threshold)
    else:
        # Use launch credit as threshold
        print('Use launch credit as threshold.')
        threshold = credits_used_per_vcpu_hour
        desc = 'Raise alarm when CPUCreditBalance drops below launch credit: {}'.format(
            threshold)

    try:
        api_response = cloudwatch_client.put_metric_alarm(
            AlarmName=alarm_name,
            AlarmDescription=desc,
            ActionsEnabled=True,
            MetricName='CPUCreditBalance',
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
            ComparisonOperator='LessThanOrEqualToThreshold',
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

# Get config values from parameter store.
def get_configuration_data():
    try:
        get_threshold:Dict[str,Any] = ssm_client.get_parameter(Name=os.environ.get('THRESHOLD'))
        threshold = get_threshold['Parameter']['Value']

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
