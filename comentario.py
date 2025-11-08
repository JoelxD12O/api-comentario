import boto3
import uuid
import os
import json

s3 = boto3.client('s3')
dynamodb = boto3.resource('dynamodb')

def _parse_body(event):
    body = event.get('body')
    if isinstance(body, dict):
        return body
    if isinstance(body, str) and body.strip():
        try:
            return json.loads(body)
        except Exception:
            pass
    return {}

def lambda_handler(event, context):
    print("EVENT:", event)

    data = _parse_body(event)
    tenant_id = data.get('tenant_id')
    texto = data.get('texto')

    if not tenant_id or not texto:
        return {
            'statusCode': 400,
            'body': json.dumps({'error': 'tenant_id y texto son requeridos'})
        }

    table_name = os.environ['TABLE_NAME']
    bucket_name = os.environ['INGEST_BUCKET']

    # Preparar item
    uuidv1 = str(uuid.uuid1())
    comentario = {
        'tenant_id': tenant_id,
        'uuid': uuidv1,
        'detalle': {'texto': texto}
    }

    # 1) Guardar en DynamoDB
    table = dynamodb.Table(table_name)
    ddb_resp = table.put_item(Item=comentario)

    # 2) Empujar a S3 como archivo JSON (estrategia Push)
    key = f"{os.environ.get('AWS_STAGE', os.environ.get('STAGE', 'dev'))}/{tenant_id}/{uuidv1}.json"
    s3.put_object(
        Bucket=bucket_name,
        Key=key,
        Body=json.dumps(comentario, ensure_ascii=False).encode('utf-8'),
        ContentType='application/json'
    )

    return {
        'statusCode': 200,
        'body': json.dumps({
            'ok': True,
            'comentario': comentario,
            's3': {'bucket': bucket_name, 'key': key},
            'dynamodb_response': ddb_resp}
        )
    }
