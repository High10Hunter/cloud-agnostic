#!/bin/bash
set -euo pipefail

KIND_CLUSTER_NAME="capi-bootstrap"
KIND_CONFIG="./bootstrap/kind.yaml"
REGION="${1:-us-east-1}"
CLUSTERCTL_CONFIG="./bootstrap/clusterctl-config.yaml"

attach_ebs_policy_to_nodes_role() {
  local policy_arn="arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"

  echo "🔎 Locating nodes role created by CAPA stack..."
  local role_name
  role_name="$(aws iam list-roles \
    --query 'Roles[?contains(RoleName, `nodes.cluster-api-provider-aws.sigs.k8s.io`)].RoleName' \
    --output text)"

  if [[ -z "$role_name" || "$role_name" == "None" ]]; then
    echo "⚠️  Could not find nodes role by name heuristic. Listing roles..."
    aws iam list-roles --query 'Roles[].RoleName' --output text | tr '\t' '\n' | sort
    echo "❌ Aborting: nodes role not found. Ensure CAPA IAM stack finished."
    exit 1
  fi

  echo "✅ Found nodes role: $role_name"
  echo "⏳ Verifying role existence..."
  for i in {1..10}; do
    if aws iam get-role --role-name "$role_name" >/dev/null 2>&1; then
      break
    fi
    sleep 3
  done

  if aws iam list-attached-role-policies --role-name "$role_name" \
    --query "AttachedPolicies[?PolicyArn=='${policy_arn}'] | length(@)" \
    --output text | grep -q '^1$'; then
    echo "ℹ️  AmazonEBSCSIDriverPolicy already attached to $role_name. Skipping."
    return 0
  fi

  echo "🔗 Attaching AmazonEBSCSIDriverPolicy to $role_name ..."
  aws iam attach-role-policy --role-name "$role_name" --policy-arn "$policy_arn"

  echo "✅ Attached. Current policies on role:"
  aws iam list-attached-role-policies --role-name "$role_name" \
    --query "AttachedPolicies[].PolicyName" --output text | tr '\t' '\n' | sort
}

# --- Step 1: Create Kind cluster if it doesn't exist ---
if ! sudo kind get clusters | grep -q "^${KIND_CLUSTER_NAME}$"; then
  echo "Creating ephemeral bootstrap Kind cluster '${KIND_CLUSTER_NAME}'..."
  sudo kind create cluster --name "$KIND_CLUSTER_NAME" --config "$KIND_CONFIG"
else
  echo "Kind cluster '${KIND_CLUSTER_NAME}' already exists. Reusing it."
fi

sudo kubectl config use-context "kind-${KIND_CLUSTER_NAME}" >/dev/null
echo "✅ Bootstrap cluster ready: ${KIND_CLUSTER_NAME}"

# --- Step 2: Create or update CloudFormation stack ---
CFN_STACK_NAME="cluster-api-provider-aws-sigs-k8s-io"
echo "Checking AWS CloudFormation stack '${CFN_STACK_NAME}' in region '${REGION}'..."

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

# --- NEW Step 2b: Ensure nodes role has EBS CSI permissions ---
attach_ebs_policy_to_nodes_role

# --- Step 3: Initialize Cluster API with AWS provider ---
echo "Checking if Cluster API is already initialized with AWS provider..."
if sudo kubectl get crd awsmachinepools.infrastructure.cluster.x-k8s.io &>/dev/null; then
  echo "ℹ️  AWS infrastructure provider already initialized. Skipping clusterctl init."
else
  echo "Initializing Cluster API with AWS infrastructure provider..."
  export AWS_B64ENCODED_CREDENTIALS=$(clusterawsadm bootstrap credentials encode-as-profile --region "$REGION")
  clusterctl init --infrastructure aws --config "$CLUSTERCTL_CONFIG"
  echo "✅ Cluster API initialized with AWS provider."
fi
