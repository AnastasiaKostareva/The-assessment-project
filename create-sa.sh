#!/bin/bash
SA_NAME="rating-sa"
yc iam service-account create --name "$SA_NAME" 2>/dev/null || true
SA_ID=$(yc iam service-account get "$SA_NAME" --format json | jq -r '.id')
yc iam key create --service-account-id "$SA_ID" --output key.json

FOLDER_ID=$(yc config get folder-id)
yc resource-manager folder add-access-binding --id "$FOLDER_ID" --role serverless.functions.invoker --subject serviceAccount:"$SA_ID"
yc resource-manager folder add-access-binding --id "$FOLDER_ID" --role ydb.editor --subject serviceAccount:"$SA_ID"
yc resource-manager folder add-access-binding --id "$FOLDER_ID" --role storage.editor --subject serviceAccount:"$SA_ID"