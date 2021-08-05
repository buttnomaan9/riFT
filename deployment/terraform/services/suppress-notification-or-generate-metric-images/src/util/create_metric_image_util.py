'''
This function generates metric images.
'''
import json
import os
from botocore.exceptions import ClientError
from typing import Dict, Any, List
from pprint import pprint
from datetime import datetime, timedelta
import uuid
from collections import namedtuple

from .create_processes_metric_image_util import generate_processes_metrics_image

AlarmStateChangeData = namedtuple('AlarmStateChangeData', [
                                  'period', 'queryDate', 'recentDatapoints', 'startDate', 'statistic', 'threshold', 'version','evaluatedDatapoints'])

INSTANCE_ID = slice(0, 19)

def create_metric_images_urls(alarm_details, metric_names, aws_services, instance_type):
    metric_images_urls: Dict[str, str] = {}
    try:
        alarm_name: str = alarm_details['AlarmName']
        instance_id: str = alarm_name[INSTANCE_ID]

        metric_alarms_new_state_details: Dict[str, Any] = get_alarms_new_state_data(
            alarm_details, aws_services)
        for name in metric_names:
            image_url = generate_processes_metrics_image(instance_type, instance_id, name, metric_alarms_new_state_details['CPUUtilization'], aws_services) \
                if 'procstat' in name else generate_metric_image(instance_id, name, metric_alarms_new_state_details[name], aws_services)

            print(f'{name} metric image url of instance {instance_id}.')
            print(f'{image_url}')
            if image_url is not None:
                metric_images_urls[name] = image_url 

    except (Exception, ClientError) as err:
        print(err)
        print(
            f'Failed to generate {metric_names} metric images of instance {instance_id} because of above err.')
        raise err
    else:
        return metric_images_urls


def get_alarms_new_state_data(alarm_details: Dict[str, Any], aws_services: Dict[str, Any]) -> Dict[str, Any]:
    print('Get alarms history.')
    cloudwatch_resource = aws_services['cloudwatch_resource']
    child_alarms_details: List[Dict[str, Any]
                               ] = alarm_details['TriggeringChildren']
    alarm_names: List[str] = []
    today = datetime.utcnow()
    year, month, day = today.year, today.month, today.day
    alarms_new_state: Dict[str, Any] = {}
    try:
        for alarm in child_alarms_details:
            _, _, _, _, _, _, alarm_name = alarm['Arn'].split(':')
            alarm_names.append(alarm_name)
        print(alarm_names)
        for alarm_name in alarm_names:
            alarm = cloudwatch_resource.Alarm(alarm_name)
            history: Dict[str, Any] = alarm.describe_history(AlarmTypes=[
                'MetricAlarm',
            ],
                HistoryItemType='StateUpdate',
                #StartDate=datetime(year, month, day),
                #EndDate=datetime.utcnow(),
                MaxRecords=1,#Get the record of transition from OK to ALARM.
                ScanBy='TimestampDescending')

            for item in history['AlarmHistoryItems']:
                print(item['AlarmName'])
                history_data: Dict[str, Any] = json.loads(item['HistoryData'])
                print(history_data)
                new_state_data: Dict[str, Any] = history_data['newState'][
                    'stateReasonData'] if history_data['newState']['stateValue'] == 'ALARM' else None
                if new_state_data is not None:
                    alarms_new_state['CPUUtilization' if 'CPUUtilization' in alarm_name else 'CPUCreditBalance'] = {'stateReason': history_data['newState']['stateReason'],
                                                                                                                    'stateReasonData': AlarmStateChangeData(**new_state_data)}

    except Exception as err:
        print(err)
        print(
            f'Failed to retrieve new state data of {alarm_names} from  history.')
    pprint(alarms_new_state)
    return alarms_new_state


def generate_metric_image(instance_id: str, metric_name: str, alarm_new_state: Dict[str, Any], aws_services: Dict[str, Any]) -> str:
    try:
        aws_region: str = os.environ.get('AWS_REGION')
        cloudwatch_client = aws_services['cloudwatch_client']
        s3_bucket: str = os.environ.get('S3_BUCKET_TO_STORE_GENERATED_IMAGES')
        horizontal_annotation: List[Dict[str:Any]] = []
        horizontal_annotation.append({
            "color": "#ff6961",
            "label": '{}'.format(alarm_new_state['stateReason']),
            # "fill": "above",
            "value": float('{}'.format(alarm_new_state['stateReasonData'].threshold))
        })
        for datapoint in alarm_new_state['stateReasonData'].recentDatapoints:
            horizontal_annotation.append({
                "color": "#ff6961",
                "label": datapoint,
                # "fill": "above",
                "value": float(datapoint)
            })
        metric_request: Dict[str:Any] = {
            "metrics": [
                ["AWS/EC2",
                 f'{metric_name}',
                 "InstanceId", f'{instance_id}',
                 {
                     "stat": '{}'.format(alarm_new_state['stateReasonData'].statistic),
                             "period": int('{}'.format(alarm_new_state['stateReasonData'].period))

                 }]
            ],
            "height": 1024,
            "width": 1024,
            # "timezone": "+1100",
            "start": "-PT3H",
            "end": "+PT1H",
            "liveData": True,
            "annotations": {
                "horizontal": horizontal_annotation,
                "vertical": [
                    {

                        "color": "#9467bd",
                        "label": "start",
                        # "value":"2018-08-28T15:25:26Z",
                        # "value":  (datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")),
                        "value": datetime.strptime('{}'.format(alarm_new_state['stateReasonData'].startDate), "%Y-%m-%dT%H:%M:%S.%f+0000").strftime("%Y-%m-%dT%H:%M:%SZ"),
                        # "fill": "after"
                    },
                    {
                        "color": "#9467bd",
                        "value": datetime.strptime('{}'.format(alarm_new_state['stateReasonData'].queryDate), "%Y-%m-%dT%H:%M:%S.%f+0000").strftime("%Y-%m-%dT%H:%M:%SZ"),
                        "label": "end"

                    }
                ]
            }

        }
        print(f'{metric_request}')
        response = cloudwatch_client.get_metric_widget_image(
            MetricWidget=json.dumps(metric_request)
            # OutputFormat='string'
        )
        image_name: str = f'{uuid.uuid4().hex}.jpeg'
        upload_image_to_s3(
            image_name, response["MetricWidgetImage"], aws_services)
    except Exception as err:
        print(err)
        print('Failed because of above error.')
    else:
        return f'https://{s3_bucket}.s3-{aws_region}.amazonaws.com/{image_name}'


def upload_image_to_s3(image_name: str, image: bytearray, aws_services: Dict[str, Any]):
    try:

        s3_resource = aws_services['s3_resource']
        s3_bucket: str = os.environ.get('S3_BUCKET_TO_STORE_GENERATED_IMAGES')
        bucket = s3_resource.Bucket(f'{s3_bucket}')
        bucket.put_object(Key=image_name,
                          ACL='public-read',
                          Body=image,
                          ContentType='image/jpeg'
                          )
    except Exception as err:
        print(err)
        print('Failed because of above error')
