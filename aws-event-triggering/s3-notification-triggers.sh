#!/bin/bash

set -x

# Store the AWS account ID in a variable
aws_account_id=$(aws sts get-caller-identity --query 'Account' --output text)

# Print the AWS account ID from the variable
echo "AWS Account ID: $aws_account_id"

# Set AWS region and bucket name
AWS_REGION="us-east-1"
lambda_func_name="s3-lambda-function"
role_name="s3-lambda-sns"
email_address="sakthibazz@gmail.com"

# Function to create an SNS topic
function create_sns_topic() {
  local topic_name=$1
  aws sns create-topic --name "$topic_name" --output json | jq -r '.TopicArn'
}

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
  if aws s3api head-bucket --bucket "$BUCKET_NAME" --region "$AWS_REGION" 2>/dev/null; then
    echo "Bucket '$BUCKET_NAME' already exists."
  else
    # Create the bucket
    aws s3api create-bucket --bucket "$BUCKET_NAME" --region "$AWS_REGION" 
    if [ $? -eq 0 ]; then
      echo "Bucket '$BUCKET_NAME' created successfully."
      break  # Exit the loop if the bucket is created successfully
    else
      echo "Failed to create the bucket '$BUCKET_NAME'."
    fi
  fi
done

# Print the output from the variable
echo "Bucket creation output: $BUCKET_NAME"

# Upload a file to the bucket
aws s3 cp ./example_file.txt "s3://$BUCKET_NAME/example_file.txt"

# Create a Zip file to upload Lambda Function
zip -r s3-lambda-function.zip ./s3-lambda-function

# Create a Lambda function
aws lambda create-function \
  --region "$AWS_REGION" \
  --function-name "$lambda_func_name" \
  --runtime "python3.8" \
  --handler "s3-lambda-function/s3-lambda-function.lambda_handler" \
  --memory-size 128 \
  --timeout 30 \
  --role "$role_arn" \
  --zip-file "fileb://./s3-lambda-function.zip"

# Create an SNS topic or get the ARN of an existing one
existing_topic_arn=$(aws sns list-topics --output json | jq -r '.Topics[] | select(.TopicArn | contains(":s3-lambda-sns")) | .TopicArn')
if [ -n "$existing_topic_arn" ]; then
  topic_arn="$existing_topic_arn"
  echo "SNS Topic already exists: $topic_arn"
else
  topic_arn=$(create_sns_topic "s3-lambda-sns")
  echo "SNS Topic ARN: $topic_arn"
fi

# Add SNS publish permission to the Lambda Function
permission_statement_id="sns-publish"
if aws lambda get-policy --function-name "$lambda_func_name" | jq -r --arg sid "$permission_statement_id" '.Policy | fromjson | .Statement[]? | select(.Sid == $sid) | .Sid' | grep -q "$permission_statement_id"; then
  echo "Permission '$permission_statement_id' already exists for Lambda function."
else
  aws lambda add-permission \
    --function-name "$lambda_func_name" \
    --statement-id "$permission_statement_id" \
    --action "lambda:InvokeFunction" \
    --principal sns.amazonaws.com \
    --source-arn "$topic_arn"
fi

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
