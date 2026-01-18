#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
cd "$SCRIPT_DIR"

command -v yc >/dev/null || { echo "yc CLI не установлен"; exit 1; }
command -v jq >/dev/null || { echo "jq не установлен"; exit 1; }
[[ -f key.json ]] || { echo "key.json не найден"; exit 1; }

SA_ID=$(jq -r '.service_account_id' key.json)
[[ -n "$SA_ID" && "$SA_ID" != "null" ]] || { echo "Неверный key.json"; exit 1; }

TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

cp app.py requirements.txt "$TEMP_DIR/"
(cd "$TEMP_DIR" && zip -q app.zip app.py requirements.txt)

yc serverless function create --name project-rating-app --description "Оценка проекта" 2>/dev/null || true

yc serverless function version create \
  --function-name project-rating-app \
  --runtime python311 \
  --entrypoint app.handler \
  --memory 128m \
  --execution-timeout 60s \
  --source-path "$TEMP_DIR/app.zip" \
  --environment YDB_ENDPOINT=grpcs://ydb.serverless.yandexcloud.net:2135 \
  --environment YDB_DATABASE=/ru-central1/b1gdfge8kaash1qqcm0e/etnduu2te3ri87mic2n2 \
  --service-account-id "$SA_ID" \
  --format json >/dev/null

FUNCTION_ID=$(yc serverless function get project-rating-app --format json | jq -r '.id')
echo "Функция: $FUNCTION_ID"

cat > "$TEMP_DIR/gateway.yaml" <<EOF
openapi: 3.0.0
info:
  title: project-rating-gateway
  version: 1.0.0
paths:
  /api/version:
    get:
      x-yc-apigateway-integration:
        type: cloud_functions
        function_id: $FUNCTION_ID
        service_account_id: $SA_ID
        timeout: 60s
        content: { pass: true }
        context: { pass: true }
      responses: { '200': { description: OK } }
  /api/rate:
    post:
      x-yc-apigateway-integration:
        type: cloud_functions
        function_id: $FUNCTION_ID
        service_account_id: $SA_ID
        timeout: 60s
        content: { pass: true }
        context: { pass: true }
      responses: { '200': { description: OK } }
  /api/ratings:
    get:
      x-yc-apigateway-integration:
        type: cloud_functions
        function_id: $FUNCTION_ID
        service_account_id: $SA_ID
        timeout: 60s
        content: { pass: true }
        context: { pass: true }
      responses: { '200': { description: OK } }
  /health:
    get:
      x-yc-apigateway-integration:
        type: cloud_functions
        function_id: $FUNCTION_ID
        service_account_id: $SA_ID
        timeout: 60s
        content: { pass: true }
        context: { pass: true }
      responses: { '200': { description: OK } }
EOF

yc serverless api-gateway create --name project-rating-gateway --spec "$TEMP_DIR/gateway.yaml" 2>/dev/null || \
yc serverless api-gateway update --name project-rating-gateway --spec "$TEMP_DIR/gateway.yaml"

echo "Ожидание API Gateway"
GATEWAY_DOMAIN=""
for i in {1..20}; do
  GATEWAY_DOMAIN=$(yc serverless api-gateway list --format json | \
    jq -r '.[] | select(.name == "project-rating-gateway") | .domain // empty')
  if [[ -n "$GATEWAY_DOMAIN" && "$GATEWAY_DOMAIN" != "null" ]]; then
    echo "Gateway: https://$GATEWAY_DOMAIN"
    break
  fi
  echo "Попытка $i/20..."
  sleep 3
done

if [[ -z "$GATEWAY_DOMAIN" || "$GATEWAY_DOMAIN" == "null" ]]; then
  echo "Не найден активный gateway"
  exit 1
fi

BUCKET_NAME="rating-assessment-project-ydb-course"

yc storage bucket create --name "$BUCKET_NAME" 2>/dev/null || true
yc storage bucket update --name "$BUCKET_NAME" --public-read

sed "s|__GATEWAY_DOMAIN__|$GATEWAY_DOMAIN|" index.html.template > "$TEMP_DIR/index.html"
aws s3 cp "$TEMP_DIR/index.html" "s3://$BUCKET_NAME/" \
  --endpoint-url https://storage.yandexcloud.net

FRONTEND_URL="https://$BUCKET_NAME.storage.yandexcloud.net/index.html"


echo "Деплой завершён"
echo "Фронтенд: $FRONTEND_URL"
echo "API: https://$GATEWAY_DOMAIN"