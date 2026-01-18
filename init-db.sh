#!/bin/bash
set -e

echo "Инициализируем YDB"
python3 -c "
import ydb, subprocess
token = subprocess.check_output(['yc', 'iam', 'create-token'], text=True).strip()
driver = ydb.Driver(
    endpoint='grpcs://ydb.serverless.yandexcloud.net:2135',
    database='/ru-central1/b1gdfge8kaash1qqcm0e/etnduu2te3ri87mic2n2',
    credentials=ydb.credentials.AuthTokenCredentials(token),
    root_certificates=ydb.load_ydb_root_certificate()
)
driver.wait(timeout=10)
session = driver.table_client.session().create()
session.execute_scheme('CREATE TABLE IF NOT EXISTS ratings (id Uint64, name Text, rating Uint8, created_at Timestamp, PRIMARY KEY (id))')
print('Таблица ratings готова')
driver.stop()
"