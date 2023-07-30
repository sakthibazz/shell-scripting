#!/bin/bash

set -x

# Store the AWS account ID in a variable
aws_account_id=$(aws sts get-caller-identity --query 'Account' --output text)

# Print the AWS account ID from the variable
echo "AWS Account ID: $aws_account_id"

# Set AWS region and bucket name
AWS_REGION="us-east-1"
lambda_func_name="s3-lambda-function-new"
role_name="s3-lambda-sns-new"
email_address="sakthiglmech123@gmail.com"


# Checking if the IAM role already exists
if aws iam get-role --role-name "$role_name" 2>/dev/null; then
  # Detach policies from the IAM role
  aws iam list-attached-role-policies --role-name "$role_name" | jq -r '.AttachedPolicies | .[].PolicyArn' | while read policy_arn; do
    aws iam detach-role-policy --role-name "$role_name" --policy-arn "$policy_arn"
  done

  # Delete the IAM role
  aws iam delete-role --role-name "$role_name"
fi

# Creating the IAM role
role_response=$(aws iam create-role --role-name "$role_name" --assume-role-policy-document '{
  "Version": "2012-10-17",
  "Statement": [{
    "Action": "sts:AssumeRole",
    "Effect": "Allow",
    "Principal": {
      "Service": [
        "lambda.amazonaws.com",
        "s3.amazonaws.com",
        "sns.amazonaws.com"
      ]
    }
  }]
}')

# Extract the role ARN from the JSON response and store it in a variable
role_arn=$(echo "$role_response" | jq -r '.Role.Arn')

# Print the role ARN
echo "Role ARN: $role_arn"

# Attach Permissions to the Role
aws iam attach-role-policy --role-name "$role_name" --policy-arn arn:aws:iam::aws:policy/AWSLambda_FullAccess
aws iam attach-role-policy --role-name "$role_name" --policy-arn arn:aws:iam::aws:policy/AmazonSNSFullAccess

# Create the S3 bucket and capture the output in a variable
for ((i=1; i<=1000; i++)); do
  BUCKET_NAME="sakthinewdevops$i"

  # Check if the bucket already exists
  if ! aws s3api head-bucket --bucket "$BUCKET_NAME" --region "$AWS_REGION" 2>/dev/null; then
    # Create the bucket
    aws s3api create-bucket --bucket "$BUCKET_NAME" --region "$AWS_REGION" 

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
bucket_name="$BUCKET_NAME"

# Print the output from the variable
echo "Bucket creation output: $bucket_name"

# Upload a file to the bucket
aws s3 cp ./example_file.txt "s3://$bucket_name/example_file.txt"

# Create a Zip file to upload Lambda Function
zip -r s3-lambda-function.zip ./s3-lambda-function

sleep 30
# Create a Lambda function
aws lambda create-function \
  --region "$AWS_REGION" \
  --function-name "$lambda_func_name" \
  --runtime "python3.8" \
  --handler "s3-lambda-function/s3-lambda-function.lambda_handler" \
  --memory-size 128 \
  --timeout 30 \
  --role "arn:aws:iam::$aws_account_id:role/$role_name" \
  --zip-file "fileb://./s3-lambda-function.zip"

# Add Permissions to S3 Bucket to invoke Lambda
aws lambda add-permission \
  --function-name "$lambda_func_name" \
  --statement-id "s3-lambda-sns" \
  --action "lambda:InvokeFunction" \
  --principal s3.amazonaws.com \
  --source-arn "arn:aws:s3:::$bucket_name"

# Create an S3 event trigger for the Lambda function
LambdaFunctionArn="arn:aws:lambda:$AWS_REGION:$aws_account_id:function:$lambda_func_name"
aws s3api put-bucket-notification-configuration \
  --region "$AWS_REGION" \
  --bucket "$bucket_name" \
  --notification-configuration '{
    "LambdaFunctionConfigurations": [{
        "LambdaFunctionArn": "'"$LambdaFunctionArn"'",
        "Events": ["s3:ObjectCreated:*"]
    }]
}'

# Create an SNS topic and save the topic ARN to a variable
topic_arn=$(aws sns create-topic --name s3-lambda-sns-new --output json | jq -r '.TopicArn')

# Print the TopicArn
echo "SNS Topic ARN: $topic_arn"

# Add SNS publish permission to the Lambda Function
aws lambda add-permission \
  --function-name "$lambda_func_name" \
  --statement-id "sns-publish" \
  --action "lambda:InvokeFunction" \
  --principal sns.amazonaws.com \
  --source-arn "$topic_arn"

# Subscribe Lambda function to the SNS topic
aws sns subscribe \
  --topic-arn "$topic_arn" \
  --protocol "lambda" \
  --notification-endpoint "$LambdaFunctionArn"

# Publish to the SNS topic
aws sns publish \
  --topic-arn "$topic_arn" \
  --subject "A new object created in S3 bucket" \
  --message "Hello from Abhishek.Veeramalla YouTube channel, Learn DevOps Zero to Hero for Free"
