import os
import boto3
from botocore.exceptions import ClientError
from typing import Dict, Any, List
from pprint import pprint
import pymsteams

aws_services: Dict[str, Any] = {}
aws_region: str = os.environ.get('AWS_REGION')


aws_services['ec2_resource'] = boto3.resource('ec2')
aws_services['cw_events_client'] = boto3.client('events')
aws_services['ec2_client'] = boto3.client('ec2')
aws_services['secretsmanager_client'] = boto3.client('secretsmanager')
aws_services['cloudwatch_client'] = boto3.client('cloudwatch')
aws_services['s3_resource'] = boto3.resource('s3')
aws_services['cloudwatch_resource'] = boto3.resource('cloudwatch')
aws_services['ssm_client'] = boto3.resource('ssm')

color_codes: Dict[str, str] = {'ALARM': '#fc2003',
                               'OK': '#fcad03'}

process_metric_name: Dict[str, str] = {'Windows': 'procstat cpu_usage',
                                       'Linux': 'procstat_cpu_usage'}


def lambda_handler(event, context):
    '''
    This lambda function sends alarm state change notifications to MS Teams channel.
    '''
    res_message: str = ''
    try:
        pprint(event)
        webhook_url_ssm_param = os.getenv('MS_TEAMS_WEB_HOOK_URL')
        # Get the Webhook URL from the SSM Parameter Store.
        webhook_url = aws_services['ssm_client'].get_parameter(Name=webhook_url_ssm_param)
        
        alarm_details: Dict[str:Any] = event['detail']['alarm-details']
        alarm_name: str = alarm_details['AlarmName']
        instance_id: str = alarm_name[:19]
        instance_type: str = event['details']['instance-type']
        app: str = event['detail']['app']
        platform: str = event['detail']['platform']

        metric_images_urls: Dict[str,
                                 str] = event['detail']['metric-images-urls']
        suppress_api_url: str = event['detail']['suppress-api-url']
        console_alarm_url: str = f'https://{aws_region}.console.aws.amazon.com/cloudwatch/home?region={aws_region}#alarmsV2:alarm/{alarm_name}'

        print(f'Generated suppressed api url. \n {suppress_api_url}')

        message_title: str = f'CPU credits and utilization thresholds have breached for instance {instance_id} of application {app}. \n\n'

        ms_teams_message_card = pymsteams.connectorcard(webhook_url)

        ms_teams_message_card.summary(message_title)
        ms_teams_message_card.addSection(build_message_card_section(
            message_title,
            app,
            instance_type,
            alarm_details))
        ms_teams_message_card.addSection(
            build_message_card_image_section('CPU Credit Balance', metric_images_urls['CPUCreditBalance']))
        ms_teams_message_card.addSection(
            build_message_card_image_section('CPU Utilization', metric_images_urls['CPUUtilization']))

        if process_metric_name[platform] in metric_images_urls:
            ms_teams_message_card.addSection(
                build_message_card_image_section('Processes CPU Usage', metric_images_urls[process_metric_name[platform]]))

        myTeamsPotentialAction1 = pymsteams.potentialaction(
            _name="Suppress Notifications")
        myTeamsPotentialAction1.addOpenURI('Suppress Notifications', [
            {'os': 'default', 'uri': suppress_api_url}])

        myTeamsPotentialAction2 = pymsteams.potentialaction(
            _name="Check the alarm")
        myTeamsPotentialAction2.addOpenURI(
            'Check the alarm', [{'os': 'default', 'uri': console_alarm_url}])

        ms_teams_message_card.addPotentialAction(myTeamsPotentialAction1)
        ms_teams_message_card.addPotentialAction(myTeamsPotentialAction2)

        ms_teams_message_card.color(
            color_codes[alarm_details['NewStateValue']])
        web_hook_response = ms_teams_message_card.send()

        res_message = f'Posted message to MS teams channel: {web_hook_response}'
        print(f'{res_message}')

    except (Exception, ClientError) as err:
        print(err)
        raise err
    else:
        return {'status_code': 200}


def build_message_card_section(title: str, name: str, ec2_type: str, alarm_details: Dict[str, Any]):

    try:
        message_section = pymsteams.cardsection()
        message_section.activityTitle('{}'.format(title))
        message_section.addFact(f'Alarm Name', alarm_details['AlarmName'])

        message_section.addFact('Instance Type', ec2_type)

        message_section.addFact(
            f'AWS AccountId', alarm_details['AWSAccountId'])
        message_section.addFact(f'AWS Region', aws_region)

    except Exception as err:
        print(err)
        raise err
    else:
        return message_section


def build_message_card_image_section(metric_name: str, image_url: str):

    try:
        message_section = pymsteams.cardsection()
        message_section.activityTitle('{}'.format(metric_name))
        message_section.addImage(image_url, ititle=metric_name)
        message_section.linkButton(f'View Graph', image_url)

    except Exception as err:
        print(err)
        raise err
    else:
        return message_section
