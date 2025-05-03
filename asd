#!/usr/bin/env python3

import boto3
import sys
import os
import operator
from botocore.exceptions import NoCredentialsError, PartialCredentialsError, NoRegionError, ClientError

print("Fetching IAM resources with 'Name' tag, sorting, and including Console URLs...")
print("")

# --- Configuration ---
# Get region from environment variable or use a default
region = os.environ.get("AWS_DEFAULT_REGION")
if not region:
    region = os.environ.get("AWS_REGION")
if not region:
    region = "us-east-1" # Or set your preferred default region
    print(f"Warning: AWS_DEFAULT_REGION or AWS_REGION environment variable not set. Using default region: {region}", file=sys.stderr)

# Define column widths for printing
COL_WIDTHS = {
    "aws_name": 30,
    "tag_name": 30,
    "type": 10,
    "arn": 50,
    # Console URL doesn't need padding, print full string
}

# --- Helper Functions ---

def get_iam_client(region_name):
    """Initializes and returns an IAM boto3 client."""
    try:
        return boto3.client('iam', region_name=region_name)
    except (NoCredentialsError, PartialCredentialsError):
        print("Error: AWS credentials not found. Configure your credentials.", file=sys.stderr)
        sys.exit(1)
    except NoRegionError:
        print(f"Error: Region not specified. Please set AWS_REGION or use --region.", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"An unexpected error occurred creating IAM client: {e}", file=sys.stderr)
        sys.exit(1)

def get_tag_value(tags, key_name="Name"):
    """Finds a specific tag value in a list of tags."""
    if not tags:
        return ""
    for tag in tags:
        if tag.get('Key') == key_name:
            return tag.get('Value', "")
    return ""

def build_console_url(resource_type, region, resource_identifier):
    """Constructs the AWS console URL for a resource."""
    base_url = f"https://{region}.console.aws.amazon.com/iam/home#"
    if resource_type == 'user':
        return f"{base_url}/users/{resource_identifier}"
    elif resource_type == 'role':
        return f"{base_url}/roles/{resource_identifier}"
    elif resource_type == 'policy':
         # Policies use the policy name in the URL path
        return f"{base_url}/policies/{resource_identifier}"
    return "" # Unknown type


# --- Main Logic ---

iam_client = get_iam_client(region)
all_resources = []

# --- Fetch IAM Users with Pagination ---
print("Fetching IAM Users...")
try:
    paginator = iam_client.get_paginator('list_users')
    for page in paginator.paginate():
        for user in page.get('Users', []):
            user_name = user.get('UserName')
            user_arn = user.get('Arn')

            # Get tags for the user
            tag_name = ""
            try:
                tag_response = iam_client.list_user_tags(UserName=user_name)
                tag_name = get_tag_value(tag_response.get('Tags'))
            except ClientError as e:
                 # Ignore errors if list-user-tags fails (e.g., permissions)
                 # print(f"Warning: Could not get tags for user {user_name}: {e}", file=sys.stderr)
                 pass # Suppress like the bash script did

            # Only process if a "Name" tag was found
            if tag_name:
                console_url = build_console_url('user', region, user_name)
                all_resources.append({
                    "aws_name": user_name,
                    "tag_name": tag_name,
                    "type": "user",
                    "arn": user_arn,
                    "console_url": console_url
                })
except ClientError as e:
    print(f"Error fetching IAM users: {e}", file=sys.stderr)
except Exception as e:
    print(f"An unexpected error occurred while fetching users: {e}", file=sys.stderr)

print("Finished fetching IAM Users.")
print("")


# --- Fetch IAM Roles with Pagination ---
print("Fetching IAM Roles...")
try:
    paginator = iam_client.get_paginator('list_roles')
    for page in paginator.paginate():
        for role in page.get('Roles', []):
            role_name = role.get('RoleName')
            role_arn = role.get('Arn')

            # Get tags for the role
            tag_name = ""
            try:
                tag_response = iam_client.list_role_tags(RoleName=role_name)
                tag_name = get_tag_value(tag_response.get('Tags'))
            except ClientError as e:
                 # Ignore errors if list-role-tags fails (e.g., permissions)
                 # print(f"Warning: Could not get tags for role {role_name}: {e}", file=sys.stderr)
                 pass # Suppress like the bash script did


            # Only process if a "Name" tag was found
            if tag_name:
                console_url = build_console_url('role', region, role_name)
                all_resources.append({
                    "aws_name": role_name,
                    "tag_name": tag_name,
                    "type": "role",
                    "arn": role_arn,
                    "console_url": console_url
                })
except ClientError as e:
    print(f"Error fetching IAM roles: {e}", file=sys.stderr)
except Exception as e:
    print(f"An unexpected error occurred while fetching roles: {e}", file=sys.stderr)

print("Finished fetching IAM Roles.")
print("")

# --- Fetch IAM Policies (Customer Managed) with Pagination ---
# Note: This lists Customer Managed Policies (--scope Local).
# AWS managed policies typically don't have user-defined tags like "Name".
print("Fetching IAM Policies (Customer Managed)...")
try:
    paginator = iam_client.get_paginator('list_policies')
    # Specify Scope='Local' for customer managed policies
    for page in paginator.paginate(Scope='Local'):
        for policy in page.get('Policies', []):
            policy_name = policy.get('PolicyName')
            policy_arn = policy.get('Arn')

            # Get tags for the policy using its ARN
            tag_name = ""
            try:
                tag_response = iam_client.list_policy_tags(PolicyArn=policy_arn)
                tag_name = get_tag_value(tag_response.get('Tags'))
            except ClientError as e:
                 # Ignore errors if list-policy-tags fails (e.g., permissions)
                 # print(f"Warning: Could not get tags for policy {policy_name}: {e}", file=sys.stderr)
                 pass # Suppress like the bash script did


            # Only process if a "Name" tag was found
            if tag_name:
                 # Policies console URL typically uses the policy name
                 console_url = build_console_url('policy', region, policy_name)
                 all_resources.append({
                     "aws_name": policy_name,
                     "tag_name": tag_name,
                     "type": "policy",
                     "arn": policy_arn,
                     "console_url": console_url
                 })
except ClientError as e:
    print(f"Error fetching IAM policies: {e}", file=sys.stderr)
except Exception as e:
    print(f"An unexpected error occurred while fetching policies: {e}", file=sys.stderr)

print("Finished fetching IAM Policies.")
print("")

# --- Sort and Print Results ---

# Sort the collected resources
# Sort by tag_name, then type, then aws_name
all_resources.sort(key=operator.itemgetter('tag_name', 'type', 'aws_name'))

# Print header
header = (
    f"{'AWS Name':<{COL_WIDTHS['aws_name']}} | "
    f"{'Name (from Tag)':<{COL_WIDTHS['tag_name']}} | "
    f"{'Type':<{COL_WIDTHS['type']}} | "
    f"{'ARN':<{COL_WIDTHS['arn']}} | "
    f"Console URL"
)
print(header)
print("-" * len(header)) # Print separator based on header length


# Print sorted data
for resource in all_resources:
    print(
        f"{resource['aws_name']:<{COL_WIDTHS['aws_name']}} | "
        f"{resource['tag_name']:<{COL_WIDTHS['tag_name']}} | "
        f"{resource['type']:<{COL_WIDTHS['type']}} | "
        f"{resource['arn']:<{COL_WIDTHS['arn']}} | "
        f"{resource['console_url']}"
    )

print("")
print(f"Done. Found {len(all_resources)} resources with the 'Name' tag.")
