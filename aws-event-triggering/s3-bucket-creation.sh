#!/bin/bash

AWS_REGION="us-west-1"  # Replace this with your desired AWS region

for ((i=1; i<=1000; i++)); do
  BUCKET_NAME="sakthidevops$i"

  # Check if the bucket already exists
  aws s3api head-bucket --bucket "$BUCKET_NAME" --region "$AWS_REGION" 2>/dev/null

  if [ $? -ne 0 ]; then
    # Create the bucket
    aws s3api create-bucket --bucket "$BUCKET_NAME" --region "$AWS_REGION" --create-bucket-configuration LocationConstraint="$AWS_REGION"

    if [ $? -eq 0 ]; then
      echo "Bucket '$BUCKET_NAME' created successfully."
      break  # Exit the loop if the bucket is created successfully
    else
      echo "Failed to create the bucket '$BUCKET_NAME'."
    fi
  else
    echo "Bucket '$BUCKET_NAME' already exists."
  fi
done
