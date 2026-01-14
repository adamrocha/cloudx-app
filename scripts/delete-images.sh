#!/usr/bin/env bash

aws ecr list-images --repository-name cloudx-app-repo --query 'imageIds[*]' --output json | aws ecr batch-delete-image --repository-name cloudx-app-repo --image-ids file:///dev/stdin