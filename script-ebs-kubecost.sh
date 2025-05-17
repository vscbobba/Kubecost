#!/bin/bash

set -euo pipefail

# === CONFIGURATION ===
CLUSTER_NAME="kubecost-eks-cluster"
REGION="us-east-1"
NODEGROUP_NAME="linux-nodes"
ACCOUNT_ID="631231558475"  # <-- replace with your account ID
ROLE_NAME="AmazonEKS_EBS_CSI_DriverRole"

echo "=== Step 1: Creating EKS Cluster ==="
eksctl create cluster \
  --name $CLUSTER_NAME \
  --version 1.31 \
  --region $REGION \
  --nodegroup-name $NODEGROUP_NAME \
  --node-type t3.medium \
  --nodes 2 \
  --managed

echo "=== Step 2: Updating kubeconfig ==="
aws eks --region $REGION update-kubeconfig --name $CLUSTER_NAME

echo "=== Step 3: Enabling IAM OIDC Provider ==="
eksctl utils associate-iam-oidc-provider \
  --region $REGION \
  --cluster $CLUSTER_NAME \
  --approve

echo "=== Step 4: Creating IAM Role + IRSA for EBS CSI Driver ==="
eksctl create iamserviceaccount \
  --name ebs-csi-controller-sa \
  --namespace kube-system \
  --cluster $CLUSTER_NAME \
  --region $REGION \
  --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
  --approve \
  --role-name $ROLE_NAME \
  --override-existing-serviceaccounts

echo "=== Step 5: Creating ebs-csi-driver ==="  

kubectl apply -f ebs-csi-driver.yaml

echo "=== Step 6: Creating StorageClass ==="
cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ebs-sc
provisioner: ebs.csi.aws.com
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Delete
parameters:
  type: gp3
EOF

echo "=== Step 7: Creating ebs-csi-driver ==="

kubectl create namespace kubecost-eks 

kubectl apply -f kubecost-2.6.4.yaml

echo "✅ Done! EBS dynamic provisioning is set up."
echo "🔹 Use 'kubectl get pods,pvc,pv' to verify."

