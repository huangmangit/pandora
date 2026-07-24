#!/bin/bash
# Pandora 公共部署脚本
# 用法: ./deploy.sh <group> <project>
# 示例: ./deploy.sh company-a admin

set -e

GROUP=${1:?请指定分组，如 company-a}
PROJECT=${2:?请指定项目，如 admin}

echo "Deploying $GROUP/$PROJECT ..."

cd /opt/pandora  # 按实际路径修改

docker compose -f apps/$GROUP/$PROJECT/docker-compose.yml pull
docker compose -f apps/$GROUP/$PROJECT/docker-compose.yml up -d --force-recreate

echo "Deploy complete: $GROUP/$PROJECT"
