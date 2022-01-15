import boto3
import os
from botocore.exceptions import ClientError
from typing import Dict, Any
from pprint import pprint

aws_region: str = os.environ.get('AWS_REGION')
process_metric_name: Dict[str, str] = {'Windows': 'procstat cpu_usage',
                                       'Linux': 'procstat_cpu_usage'}

sns_client = boto3.client('sns')

def lambda_handler(event, context):
    '''The lambda function sends notification of alarm state to an email address. It is triggered by the EventBridge rule.'''
    response: Dict[str, Any] = {}
    try:
        pprint(event)
        alarm_details: Dict[str:Any] = event['detail']['alarm-details']
        alarm_name: str = alarm_details['AlarmName']
        instance_id: str = alarm_name[:19]
        app: str = event['detail']['app']
        platform: str = event['detail']['platform']
        
        sns_topic: str = os.environ.get('END_SUBSCRIBERS_SNS_TOPIC')
        
        timestamp = alarm_details['StateChangeTime']
        instance_and_alarm_info: str = f'CPU credits and utilization thresholds have breached for instance {instance_id} of application {app}. \n\n'

        detail1: str = '''Details:\n Alarm: {0} \n Description: {1} \n State Change: {2} \n Alarm Rule: {3} \n Timestamp: {4} \n AWS Account: {5} \n Alarm Arn: {6}
                            '''.format(alarm_details['AlarmName'],
                                        alarm_details['AlarmDescription'],
                                        alarm_details['NewStateValue'],
                                        alarm_details['AlarmRule'],
                                        timestamp,
                                        alarm_details['AWSAccountId'],
                                        alarm_details['AlarmArn'])


        response = sns_client.publish(
            TopicArn=sns_topic,
            Message=instance_and_alarm_info + detail1 + write_metric_image_urls_to_message(event,alarm_name,platform),
            Subject=event['detail']['subject'],
            MessageStructure='String'
        )
        print(response)
        print(f'Notification sent to SNS topic {sns_topic}.')

    except (Exception, ClientError) as err:
        print(err)
        print('Aborted! because of above error.')
        return err
    else:
        print('Successfully executed')
        return {'status_code': 200}

def write_metric_image_urls_to_message(event,alarm_name,platform):
    try:
        alarms_metrics_detail:str=''
        processes_detail:str=''
        metric_images_urls: Dict[str, str] = event['detail']['metric-images-urls']
        suppress_api_url: str = event['detail']['suppress-api-url'] 
        console_alarm_url: str = f'https://{aws_region}.console.aws.amazon.com/cloudwatch/home?region={aws_region}#alarmsV2:alarm/{alarm_name}'
        alarms_metrics_detail = '''Console: {0} \n Suppress alarm: {1} \n CpuCreditBalance: {2} \n CpuUtilization: {3} \n
                                        '''.format(console_alarm_url,
                                                    suppress_api_url,
                                                    metric_images_urls['CPUCreditBalance'],
                                                    metric_images_urls['CPUUtilization'])
        if hasattr(metric_images_urls,process_metric_name[platform]):                                            
            processes_detail= '''ProcessesMetric: {0} \n'''.format(metric_images_urls[process_metric_name[platform]])
    except Exception as err:
        print(err)
        print('Could not retrive metric images details.')
    finally:
        return alarms_metrics_detail+processes_detail