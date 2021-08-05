# See: http://docs.aws.amazon.com/general/latest/gr/sigv4_signing.html
import os
import base64
import datetime
import hashlib
import hmac
import urllib
import boto3
import json
from botocore.exceptions import ClientError


def generate_presigned_url(secretsmanager_client: None, instance_id: str,):
    '''
    This program creates a presigned url of the Api Gateway endpoint. 
    The logic follows standard example provided by AWS to sign a request.
    '''
    try:
        presigned_url: str = ''
        # ************* REQUEST VALUES *************
        method = 'GET'
        service = 'execute-api'
        host = os.environ.get('API_GATEWAY_HOST')
        region = os.environ.get('AWS_REGION')
        endpoint = os.environ.get('API_ENDPOINT')

        access_key, secret_key = get_secrets(secretsmanager_client)

        if access_key is None or secret_key is None:
            print('No access key is available.')
            raise Exception('No access key is available')

        # Create a date for headers and the credential string
        t = datetime.datetime.utcnow()
        # Format date as YYYYMMDD'T'HHMMSS'Z'
        amz_date = t.strftime('%Y%m%dT%H%M%SZ')
        # Date w/o time, used in credential scope
        datestamp = t.strftime('%Y%m%d')

        # ************* TASK 1: CREATE A CANONICAL REQUEST *************
        # http://docs.aws.amazon.com/general/latest/gr/sigv4-create-canonical-request.html

        # Because almost all information is being passed in the query string,
        # the order of these steps is slightly different than examples that
        # use an authorization header.

        # Step 1: Define the verb (GET, POST, etc.)--already done.

        # Step 2: Create canonical URI--the part of the URI from domain to query
        # string (use '/' if no path)
        #canonical_uri = '/test/suppress-cpu-credit-alarm'
        canonical_uri = os.environ.get('SUPPRESS_NOTIFICATION_URI')
        # Step 3: Create the canonical headers and signed headers. Header names
        # must be trimmed and lowercase, and sorted in code point order from
        # low to high. Note trailing \n in canonical_headers.
        # signed_headers is the list of headers that are being included
        # as part of the signing process. For requests that use query strings,
        # only "host" is included in the signed headers.
        canonical_headers = 'host:' + host + '\n'
        signed_headers = 'host'

        # Match the algorithm to the hashing algorithm you use, either SHA-1 or
        # SHA-256 (recommended)
        algorithm = 'AWS4-HMAC-SHA256'
        credential_scope = datestamp + '/' + region + \
            '/' + service + '/' + 'aws4_request'

        # Step 4: Create the canonical query string. In this example, request
        # parameters are in the query string. Query string values must
        # be URL-encoded (space=%20). The parameters must be sorted by name.
        # use urllib.parse.quote_plus() if using Python 3

        canonical_querystring = 'X-Amz-Algorithm=AWS4-HMAC-SHA256'
        canonical_querystring += '&X-Amz-Credential=' + \
            urllib.parse.quote_plus(access_key + '/' + credential_scope)
        canonical_querystring += '&X-Amz-Date=' + amz_date
        canonical_querystring += '&X-Amz-Expires=30'
        canonical_querystring += '&X-Amz-SignedHeaders=' + signed_headers
        canonical_querystring += '&instance-id='+instance_id
        #canonical_querystring += '&instance-id=i-011067b7cdab6fcb3'

        # Step 5: Create payload hash. For GET requests, the payload is an
        # empty string ("").
        payload_hash = hashlib.sha256(('').encode('utf-8')).hexdigest()

        # Step 6: Combine elements to create canonical request
        canonical_request = method + '\n' + canonical_uri + '\n' + canonical_querystring + \
            '\n' + canonical_headers + '\n' + signed_headers + '\n' + payload_hash
        print(f'canonical_request={canonical_request}')

        # ************* TASK 2: CREATE THE STRING TO SIGN*************
        string_to_sign = algorithm + '\n' + amz_date + '\n' + credential_scope + \
            '\n' + \
            hashlib.sha256(canonical_request.encode('utf-8')).hexdigest()

        print(f'string_to_sign={string_to_sign}')
        # ************* TASK 3: CALCULATE THE SIGNATURE *************
        # Create the signing key
        signing_key = getSignatureKey(secret_key, datestamp, region, service)

        # Sign the string_to_sign using the signing_key
        signature = hmac.new(signing_key, (string_to_sign).encode(
            "utf-8"), hashlib.sha256).hexdigest()

        # ************* TASK 4: ADD SIGNING INFORMATION TO THE REQUEST *************
        # The auth information can be either in a query string
        # value or in a header named Authorization. This code shows how to put
        # everything into a query string.
        canonical_querystring += '&X-Amz-Signature=' + signature

        presigned_url = endpoint + "?" + canonical_querystring

        print('Request URL = ' + presigned_url)
    except (ClientError, Exception) as err:
        print('Failed to generaet presigned url.')
        raise err
    else:
        return presigned_url


def sign(key, msg):
    return hmac.new(key, msg.encode('utf-8'), hashlib.sha256).digest()


def getSignatureKey(key, dateStamp, regionName, serviceName):
    kDate = sign(('AWS4' + key).encode('utf-8'), dateStamp)
    kRegion = sign(kDate, regionName)
    kService = sign(kRegion, serviceName)
    kSigning = sign(kService, 'aws4_request')
    return kSigning


def get_secrets(secretsmanager_client):
    '''Get access key and secret access key from the Secrets Manager to sign the API URL.'''
    access_key = None
    secret_key = None
    try:
        secrets_name: str = os.environ.get('CREDENTIAL_TO_SIGN_API_URL')

        get_secerts_response = secretsmanager_client.get_secret_value(
            SecretId=secrets_name
        )

        if 'SecretString' in get_secerts_response:
            secrets_json = json.loads(
                get_secerts_response['SecretString'])
            access_key = secrets_json['access_key']
            secret_key = secrets_json['secret_key']

    except Exception as err:
        print(f'Failed to get access key and secret key to sign the API url.')
        raise err
    else:
        return access_key, secret_key
