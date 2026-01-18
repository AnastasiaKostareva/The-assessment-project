#!/bin/bash
yc serverless function delete --name project-rating-app 2>/dev/null || true
yc serverless api-gateway delete --name project-rating-gateway 2>/dev/null || true

for b in $(yc storage bucket list --format json | jq -r '.[] | select(.name | startswith("rating-frontend-")) | .name'); do
  yc storage bucket delete --name "$b" 2>/dev/null || true
done