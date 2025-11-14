#!/bin/bash

# Script de déploiement automatisé pour le pipeline de données distribué
# Usage: ./deploy.sh [start|stop|restart|status|clean]

set -e

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="data-pipeline"
MINIKUBE_MEMORY="6144"
MINIKUBE_CPUS="4"

# Fonction pour afficher les messages
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Vérifier les prérequis
check_requirements() {
    log_info "Checking requirements..."
    
    # Vérifier kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed"
        exit 1
    fi
    
    # Vérifier minikube
    if ! command -v minikube &> /dev/null; then
        log_error "minikube is not installed"
        exit 1
    fi
    
    log_success "All requirements met"
}

# Démarrer Minikube
start_minikube() {
    log_info "Starting Minikube..."
    
    if minikube status &> /dev/null; then
        log_warning "Minikube is already running"
    else
        minikube start \
            --driver=docker \
            --memory=${MINIKUBE_MEMORY} \
            --cpus=${MINIKUBE_CPUS} \
            --disk-size=20g
        
        minikube addons enable metrics-server
        log_success "Minikube started successfully"
    fi
}

# Déployer l'infrastructure
deploy_infrastructure() {
    log_info "Deploying infrastructure..."
    
    # Créer le namespace
    log_info "Creating namespace..."
    kubectl apply -f namespace.yaml
    
    # Déployer Kafka
    log_info "Deploying Kafka..."
    kubectl apply -f apache_kafka/kafka_controller_statefulset.yaml
    kubectl apply -f apache_kafka/kafka_broker_statefulset.yaml
    
    # Déployer Spark
    log_info "Deploying Spark..."
    kubectl apply -f spark/spark_master_deployment.yaml
    kubectl apply -f spark/spark_worker_deployment.yaml
    kubectl apply -f spark/spark_client_statefulset.yaml
    
    # Déployer le Producer
    log_info "Deploying Python Producer..."
    kubectl apply -f python_producer/producer_deployment.yaml
    
    # Déployer le monitoring
    log_info "Deploying Monitoring Stack..."
    kubectl apply -f apache_kafka/kafka-exporter.yaml
    kubectl apply -f monitoring/prometheus-deployment.yaml
    kubectl apply -f monitoring/grafana-deployment.yaml
    
    log_success "Infrastructure deployed successfully"
}

# Attendre que les pods soient prêts
wait_for_pods() {
    log_info "Waiting for pods to be ready..."
    
    local timeout=300
    local interval=5
    local elapsed=0
    
    while [ $elapsed -lt $timeout ]; do
        ready_pods=$(kubectl get pods -n $NAMESPACE -o json | jq '.items | map(select(.status.phase == "Running")) | length')
        total_pods=$(kubectl get pods -n $NAMESPACE -o json | jq '.items | length')
        
        if [ "$ready_pods" == "$total_pods" ] && [ "$total_pods" -gt 0 ]; then
            log_success "All pods are ready ($ready_pods/$total_pods)"
            return 0
        fi
        
        echo -ne "\r⏳ Waiting for pods: $ready_pods/$total_pods ready (${elapsed}s elapsed)..."
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    log_error "Timeout waiting for pods to be ready"
    return 1
}

# Afficher le statut
show_status() {
    log_info "Cluster Status:"
    echo "=================="
    kubectl get all -n $NAMESPACE
    echo ""
    
    log_info "Pod Resource Usage:"
    kubectl top pods -n $NAMESPACE 2>/dev/null || echo "Metrics not available yet"
    echo ""
    
    log_info "Access URLs:"
    local minikube_ip=$(minikube ip)
    echo "  Prometheus: http://$minikube_ip:30090"
    echo "  Grafana: http://$minikube_ip:30030"
    echo "    Username: admin"
    echo "    Password: admin123"
}

# Démarrer le pipeline
start_pipeline() {
    log_info "Starting data pipeline..."
    
    check_requirements
    start_minikube
    deploy_infrastructure
    wait_for_pods
    
    log_info "Copying Spark job files..."
    kubectl cp spark/spark_job.py spark-client-0:/opt/spark/work-dir/spark_job.py -n $NAMESPACE
    kubectl cp spark/model_utils.py spark-client-0:/opt/spark/work-dir/model_utils.py -n $NAMESPACE
    kubectl cp spark/pretrained_models/ spark-client-0:/opt/spark/work-dir/pretrained_models/ -n $NAMESPACE
    kubectl cp spark/spark_submit.sh spark-client-0:/opt/spark/work-dir/spark_submit.sh -n $NAMESPACE
    
    log_success "Pipeline started successfully"
    show_status
}

# Arrêter le pipeline
stop_pipeline() {
    log_info "Stopping pipeline..."
    kubectl scale deployment python-producer --replicas=0 -n $NAMESPACE 2>/dev/null || true
    log_success "Pipeline stopped"
}

# Nettoyer tout
clean_all() {
    log_warning "Cleaning all resources..."
    kubectl delete namespace $NAMESPACE --ignore-not-found=true
    minikube stop
    log_success "All resources cleaned"
}

# Menu principal
case "$1" in
    start)
        start_pipeline
        ;;
    stop)
        stop_pipeline
        ;;
    restart)
        stop_pipeline
        sleep 5
        start_pipeline
        ;;
    status)
        show_status
        ;;
    clean)
        clean_all
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|clean}"
        echo ""
        echo "Commands:"
        echo "  start   - Start the complete pipeline"
        echo "  stop    - Stop the pipeline"
        echo "  restart - Restart the pipeline"
        echo "  status  - Show cluster status"
        echo "  clean   - Clean all resources"
        exit 1
        ;;
esac