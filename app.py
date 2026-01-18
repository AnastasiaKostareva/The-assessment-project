import os
import json
import uuid
import ydb
import ydb.iam
from datetime import datetime

YDB_ENDPOINT = os.getenv('YDB_ENDPOINT', 'grpcs://ydb.serverless.yandexcloud.net:2135')
YDB_DATABASE = os.getenv('YDB_DATABASE', '/ru-central1/b1gdfge8kaash1qqcm0e/etnduu2te3ri87mic2n2')
BACKEND_ID = str(uuid.uuid4())[:8]

def get_ydb_pool():
    try:
        driver = ydb.Driver(
            endpoint=YDB_ENDPOINT,
            database=YDB_DATABASE,
            credentials=ydb.iam.MetadataUrlCredentials(),
        )
        driver.wait(timeout=5, fail_fast=True)
        return ydb.SessionPool(driver)
    except Exception as e:
        print(f"YDB connection error: {e}")
        return None

pool = get_ydb_pool()

def execute_query(query, parameters=None):
    if not pool:
        raise Exception("YDB not connected")
    
    def callee(session):
        return session.transaction().execute(query, parameters, commit_tx=True)
    
    return pool.retry_operation_sync(callee)

def handler(event, context):
    print(f"Request: {event.get('httpMethod')} {event.get('path')}")

    path = event.get('path', '')
    
    if path == '/api/version' or path.endswith('/version'):
        return handle_version()
    elif path == '/api/rate':
        if event.get('httpMethod') == 'POST':
            return handle_rate(event.get('body', '{}'))
        else:
            return error_response('Method not allowed', 405)
    elif path == '/api/ratings':
        if event.get('httpMethod') == 'GET':
            return handle_get_ratings()
        else:
            return error_response('Method not allowed', 405)
    elif path == '/health':
        return handle_health()
    else:
        return error_response('Not found', 404)

def handle_version():
    return create_response({
        'version': '1.0.0',
        'backend_id': BACKEND_ID,
        'timestamp': datetime.utcnow().isoformat() + 'Z'
    })

def handle_rate(body_str):
    try:
        body = json.loads(body_str) if body_str else {}
        name = body.get('name', 'Аноним').strip() or 'Аноним'
        rating = int(body.get('rating', 0))
        if not 1 <= rating <= 10:
            return error_response('Rating must be between 1 and 10', 400)

        import time
        import random
        rating_id = int(time.time() * 1000000) + random.randint(0, 999999)

        def callee(session):
            query = f"""
            UPSERT INTO ratings (id, name, rating, created_at)
            VALUES ({rating_id}, "{name}", {rating}, CurrentUtcTimestamp())
            """
            session.transaction().execute(query, commit_tx=True)
        
        pool.retry_operation_sync(callee)

        print(f"Rating saved: {name} - {rating}")
        return create_response({
            'success': True,
            'message': 'Rating saved',
            'id': rating_id
        })

    except (ValueError, TypeError) as e:
        print(f"Validation error: {e}")
        return error_response('Rating must be a number between 1 and 10', 400)
    except Exception as e:
        print(f"Rate error: {e}")
        import traceback
        traceback.print_exc()
        return error_response(f'Server error: {str(e)}', 500)

def handle_get_ratings():
    try:
        def callee(session):
            return session.transaction().execute(
                'SELECT name, rating, created_at FROM ratings ORDER BY created_at DESC LIMIT 100',
                commit_tx=True
            )
        result = pool.retry_operation_sync(callee)

        ratings = []
        for row in result[0].rows:
            try:
                if hasattr(row.created_at, 'to_datetime'):
                    dt = row.created_at.to_datetime()
                elif hasattr(row.created_at, 'seconds'):
                    dt = datetime.utcfromtimestamp(row.created_at.seconds)
                elif isinstance(row.created_at, (int, float)):
                    dt = datetime.utcfromtimestamp(row.created_at / 1000000)
                else:
                    dt = datetime.utcnow()
            except Exception as e:
                print(f"Error converting timestamp: {e}")
                dt = datetime.utcnow()
            
            ratings.append({
                'name': row.name,
                'rating': row.rating,
                'created_at': dt.isoformat() + 'Z'
            })

        return create_response(ratings)

    except Exception as e:
        print(f"Get ratings error: {e}")
        return error_response(f'Server error: {str(e)}', 500)

def handle_health():
    return create_response({
        'status': 'healthy',
        'backend_id': BACKEND_ID,
        'ydb_connected': pool is not None,
        'timestamp': datetime.utcnow().isoformat() + 'Z'
    })

def create_response(data, status_code=200):
    return {
        'statusCode': status_code,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        'body': json.dumps(data, ensure_ascii=False)
    }

def error_response(message, code=500):
    return create_response({
        'error': message,
        'backend_id': BACKEND_ID
    }, code)