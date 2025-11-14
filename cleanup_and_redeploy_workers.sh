#!/bin/bash

echo "=== Cleaning up old Spark workers and service ==="

# 1. Delete old service if it exists
echo "Deleting old 'spark-worker' service (if exists)..."
kubectl delete svc spark-worker -n data-pipeline --ignore-not-found=true

# 2. Delete worker deployment (this will kill all pods)
echo "Deleting worker deployment..."
kubectl delete deployment spark-worker -n data-pipeline --ignore-not-found=true

# Wait for pods to be fully terminated
echo "Waiting for pods to terminate..."
kubectl wait --for=delete pod -l app=spark-worker -n data-pipeline --timeout=60s 2>/dev/null || true

# 3. Delete HPA
echo "Deleting HPA..."
kubectl delete hpa spark-worker-hpa -n data-pipeline --ignore-not-found=true

echo ""
echo "=== Redeploying with new configuration ==="

# 4. Apply the fixed configuration
echo "Applying spark_worker_deployment.yaml..."
kubectl apply -f spark/spark_worker_deployment.yaml

# 5. Wait for pods to be ready
echo ""
echo "Waiting for worker pods to start..."
kubectl wait --for=condition=ready pod -l app=spark-worker -n data-pipeline --timeout=120s

# 6. Check status
echo ""
echo "=== Current status ==="
kubectl get pods -n data-pipeline -l app=spark-worker
kubectl get svc -n data-pipeline -l app=spark-worker

echo ""
echo "=== Checking logs of first worker ==="
WORKER_POD=$(kubectl get pods -n data-pipeline -l app=spark-worker -o jsonpath='{.items[0].metadata.name}')
echo "Pod: $WORKER_POD"
kubectl logs $WORKER_POD -n data-pipeline --tail=50
