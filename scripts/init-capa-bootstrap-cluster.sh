#!/bin/bash

set -euo pipefail

KIND_CLUSTER_NAME="capi-bootstrap"
KIND_CONFIG="./bootstrap/kind.yaml"
REGION="${1:-us-east-1}"
CLUSTERCTL_CONFIG="./bootstrap/clusterctl-config.yaml"

# --- Step 1: Create Kind cluster if it doesn't exist ---
if ! sudo kind get clusters | grep -q "^${KIND_CLUSTER_NAME}$"; then
  echo "Creating ephemeral bootstrap Kind cluster '${KIND_CLUSTER_NAME}'..."
  sudo kind create cluster --name "$KIND_CLUSTER_NAME" --config "$KIND_CONFIG"
else
  echo "Kind cluster '${KIND_CLUSTER_NAME}' already exists. Reusing it."
fi

# Ensure kubectl context is set
sudo kubectl config use-context "kind-${KIND_CLUSTER_NAME}" >/dev/null

echo "✅ Bootstrap cluster ready: ${KIND_CLUSTER_NAME}"

# --- Step 2: Create or update CloudFormation stack ---
CFN_STACK_NAME="cluster-api-provider-aws-sigs-k8s-io"

echo "Checking AWS CloudFormation stack '${CFN_STACK_NAME}' in region '${REGION}'..."

# Check if stack exists and is in a stable state
stack_status=$(aws cloudformation describe-stacks \
  --stack-name "$CFN_STACK_NAME" \
  --region "$REGION" \
  --query 'Stacks[0].StackStatus' \
  --output text 2>/dev/null || true)

if [[ "$stack_status" == "" ]]; then
  echo "CloudFormation stack does not exist. Creating it..."
  clusterawsadm bootstrap iam create-cloudformation-stack --region "$REGION"
  echo "✅ CloudFormation stack created."
elif [[ "$stack_status" == "CREATE_COMPLETE" || "$stack_status" == "UPDATE_COMPLETE" ]]; then
  echo "CloudFormation stack exists and is up-to-date. Attempting update (may be no-op)..."
  if output=$(clusterawsadm bootstrap iam create-cloudformation-stack --region "$REGION" 2>&1); then
    echo "$output"
    echo "✅ CloudFormation stack updated or unchanged."
  elif echo "$output" | grep -q "No updates are to be performed"; then
    echo "$output"
    echo "ℹ️  No changes needed for CloudFormation stack."
  else
    echo "$output" >&2
    echo "❌ Unexpected error during CloudFormation update." >&2
    exit 1
  fi
else
  echo "⚠️  CloudFormation stack status is '${stack_status}'. Please resolve manually."
  exit 1
fi

# --- Step 3: Initialize Cluster API with AWS provider ---
echo "Checking if Cluster API is already initialized with AWS provider..."

# Check if the aws infrastructure provider is already installed
if sudo kubectl get crd awsmachinepools.infrastructure.cluster.x-k8s.io &>/dev/null; then
  echo "ℹ️  AWS infrastructure provider already initialized. Skipping clusterctl init."
else
  echo "Initializing Cluster API with AWS infrastructure provider..."
  export AWS_B64ENCODED_CREDENTIALS=$(clusterawsadm bootstrap credentials encode-as-profile --region "$REGION")
  clusterctl init --infrastructure aws --config "$CLUSTERCTL_CONFIG"
  echo "✅ Cluster API initialized with AWS provider."
fi
