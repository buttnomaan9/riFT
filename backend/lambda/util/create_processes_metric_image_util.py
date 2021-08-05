import json
import os
import boto3
from botocore.exceptions import ClientError
from typing import Dict, Any, List
from pprint import pprint
from datetime import datetime
import uuid


def get_metrics_metadata(instance_id: str, metric_name: str, instance_type: str, aws_services: Dict[str, Any]):
    '''
    This function generates metric images for cpu usage of processes.
    '''
    try:
        cloudwatch_client = aws_services['cloudwatch_client']
        response = cloudwatch_client.list_metrics(
            Namespace='CWAgent',
            MetricName=f'{metric_name}',
            Dimensions=[
                {
                    'Name': 'InstanceId',
                    'Value': f'{instance_id}'
                },
                {
                    'Name': 'InstanceType',
                    'Value': f'{instance_type}'
                },
                {
                    'Name': 'exe',
                    'Value': '.*'
                }
            ]
        )
        metrics_metadata: List[List[Any]] = []
        for metric_info in response['Metrics']:
            metric_dimension: List[str] = [
                metric_info['Namespace'], metric_info['MetricName']]
            for dimension in metric_info['Dimensions']:
                metric_dimension.append(dimension['Name'])
                metric_dimension.append(dimension['Value'])
            metric_dimension.append({
                "stat": 'Maximum',
                "period": int(300)
            })
            metrics_metadata.append(metric_dimension)

        print(f'{metrics_metadata}')
    except Exception as err:
        print(err)
        print('Failed because of above error.')
    else:
        return metrics_metadata


def generate_processes_metrics_image(instance_type: str, instance_id: str, metric_name: str, alarm_new_state: Dict[str, Any], aws_services: Dict[str, Any]) -> str:

    try:

        aws_region: str = os.environ.get('AWS_REGION', 'ap-southeast-2')
        cloudwatch_client = aws_services['cloudwatch_client']
        s3_bucket: str = os.environ.get('CLOUDWATCH_METRIC_IMAGES_S3_BUCKET')
        metrics_metadata: List[List[Any]] = []
        metrics_metadata = get_metrics_metadata(
            instance_id, metric_name, instance_type, aws_services)
        if metrics_metadata is None or metrics_metadata == []:
            return None
        horizontal_annotation: List[Dict[str:Any]] = []
        horizontal_annotation.append({
            "color": "#ff6961",
            "label": '{}'.format(alarm_new_state['stateReason']),
            "value": float('{}'.format(alarm_new_state['stateReasonData'].threshold))
        })
        for datapoint in alarm_new_state['stateReasonData'].recentDatapoints:
            horizontal_annotation.append({
                "color": "#ff6961",
                "label": datapoint,
                "value": float(datapoint)
            })
        metric_request: Dict[str:Any] = {
            "metrics": metrics_metadata,
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
                        "value": datetime.strptime('{}'.format(alarm_new_state['stateReasonData'].startDate), "%Y-%m-%dT%H:%M:%S.%f+0000").strftime("%Y-%m-%dT%H:%M:%SZ"),
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
        s3_bucket: str = os.environ.get('CLOUDWATCH_METRIC_IMAGES_S3_BUCKET')
        bucket = s3_resource.Bucket(f'{s3_bucket}')
        bucket.put_object(Key=image_name,
                          ACL='public-read',
                          Body=image,
                          ContentType='image/jpeg'
                          )
    except Exception as err:
        print(err)
        print('Failed because of above error')


