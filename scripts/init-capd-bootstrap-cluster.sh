#!/bin/bash

sudo kind create cluster --name capi-bootstrap --config ./bootstrap/kind.yaml
echo "Ephemeral bootstrap cluster created ☸️"
sudo kubectl config use-context kind-capi-bootstrap

echo "Initializing Cluster API with Docker infrastructure provider 🐳..."
clusterctl init --infrastructure docker --config ./bootstrap/clusterctl-config.yaml
