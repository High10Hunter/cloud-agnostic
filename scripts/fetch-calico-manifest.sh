#!/bin/bash

set -euo pipefail

# Pick a Calico version that matches your k8s minor well; v3.28 works broadly.
CALICO_VERSION="v3.28.0"
CALICO_FILE="bootstrap/calico.yaml"

# Make sure POD_CIDR is set (default to 192.168.0.0/16 if not provided)
: "${POD_CIDR:=192.168.0.0/16}"

# Fetch Calico manifest
curl -fsSL -o "${CALICO_FILE}" \
  "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/calico.yaml"

# Patch the default pod CIDR in the manifest with your chosen one
sed -i.bak "s#192\.168\.0\.0/16#${POD_CIDR}#g" "${CALICO_FILE}"

echo "Wrote ${CALICO_FILE} (Calico ${CALICO_VERSION}) with pod CIDR ${POD_CIDR}"
