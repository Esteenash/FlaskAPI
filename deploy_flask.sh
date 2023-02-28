#!/bin/bash

# Authenticate with AWS
AWS_CONFIGURE --"$HOME"/.aws/config

# Authenticate with the container registry
aws ecr-public get-login-password --region eu-west-2 | docker login --username AWS --password-stdin public.ecr.aws/t0r1n7t9

# Build the Docker image using the Dockerfile
docker build -t flask_api .

# Tag the Docker image with a unique version number
version=$(date '+%y%m%d%H%M%S')
docker tag flask_api public.ecr.aws/t0r1n7t9/flask_api:"$( "version" )"

# Push the Docker image to the container registry
docker push public.ecr.aws/t0r1n7t9/flask_api:"$( "version" )"

# Update the ECS service to use the new version of the Docker image
task_def_arn=$(aws ecs describe-services --cluster flask_cluster --services flask_service --query "services[0].taskDefinition" --output text)
new_task_def_arn=$(echo "$task_def_arn" | sed "s/:[^:]*$/:$version/")
aws ecs update-service --cluster flask_cluster --service flask_service --task-definition new_task_def_arn

# Run a health check on the API endpoint to ensure the new version is running
api_url=$(aws ecs describe-tasks --cluster flask_cluster --tasks "(aws ecs list-tasks --cluster flask_cluster --service-name flask_service --query "taskArns[]" --output text) --query "tasks[0].containers[0].networkInterfaces[0].privateIpv4Address" --output text)
health_check=$(curl -s -o /dev/null -w "%{http_code}" http://$(api_url):5000/api/health)
if [ $("health_check") -ne 200 ]; then
    echo "Health check failed. Rolling back to the previous version."
    aws ecs update-service --cluster flask_cluster --service flask_service --task-definition task_def_arn
    exit 1
fi

echo "Deployment successful"