# Makefile pour gérer le pipeline de données distribué sur Kubernetes
.PHONY: all start-minikube deploy-all start-pipeline stop-pipeline clean-all monitoring

# Variables
NAMESPACE = data-pipeline
KUBECTL = kubectl
MINIKUBE = minikube

# Démarrage complet du pipeline
all: start-minikube deploy-all wait-ready start-pipeline monitoring-info

# Démarrer Minikube
start-minikube:
	@echo "🚀 Starting Minikube..."
	$(MINIKUBE) start --driver=docker --memory=6144 --cpus=4 --disk-size=20g
	$(MINIKUBE) addons enable metrics-server
	@echo "✅ Minikube started successfully"

# Déployer tous les composants
deploy-all: deploy-namespace deploy-kafka deploy-spark deploy-producer deploy-monitoring
	@echo "✅ All components deployed successfully"

# Créer le namespace
deploy-namespace:
	@echo "📦 Creating namespace..."
	$(KUBECTL) apply -f k8s-configs/00-namespace.yaml

# Déployer Kafka
deploy-kafka:
	@echo "📦 Deploying Kafka..."
	$(KUBECTL) apply -f k8s-configs/01-kafka-controller.yaml
	$(KUBECTL) apply -f k8s-configs/02-kafka-broker.yaml
	@echo "⏳ Waiting for Kafka to be ready..."
	$(KUBECTL) wait --for=condition=ready pod -l app=kafka-controller -n $(NAMESPACE) --timeout=300s
	$(KUBECTL) wait --for=condition=ready pod -l app=kafka-broker -n $(NAMESPACE) --timeout=300s

# Déployer Spark
deploy-spark:
	@echo "📦 Deploying Spark..."
	$(KUBECTL) apply -f k8s-configs/03-spark-master.yaml
	$(KUBECTL) apply -f k8s-configs/04-spark-worker.yaml
	$(KUBECTL) apply -f k8s-configs/05-spark-client.yaml
	@echo "⏳ Waiting for Spark to be ready..."
	$(KUBECTL) wait --for=condition=ready pod -l app=spark-master -n $(NAMESPACE) --timeout=300s
	$(KUBECTL) wait --for=condition=ready pod -l app=spark-worker -n $(NAMESPACE) --timeout=300s

# Déployer le Producer Python
deploy-producer:
	@echo "📦 Deploying Python Producer..."
	$(KUBECTL) apply -f k8s-configs/06-producer-deployment.yaml

# Déployer le monitoring
deploy-monitoring:
	@echo "📦 Deploying Monitoring Stack..."
	$(KUBECTL) apply -f k8s-configs/09-kafka-exporter.yaml
	$(KUBECTL) apply -f k8s-configs/07-prometheus.yaml
	$(KUBECTL) apply -f k8s-configs/08-grafana.yaml
	@echo "⏳ Waiting for monitoring to be ready..."
	$(KUBECTL) wait --for=condition=ready pod -l app=prometheus -n $(NAMESPACE) --timeout=120s
	$(KUBECTL) wait --for=condition=ready pod -l app=grafana -n $(NAMESPACE) --timeout=120s

# Attendre que tout soit prêt
wait-ready:
	@echo "⏳ Waiting for all pods to be ready..."
	$(KUBECTL) wait --for=condition=ready pod --all -n $(NAMESPACE) --timeout=300s
	@echo "✅ All pods are ready"

# Démarrer le pipeline de traitement
start-pipeline:
	@echo "🔄 Starting data pipeline..."
	@echo "📋 Copying Spark job files to client..."
	$(KUBECTL) cp spark/spark_job.py spark-client-0:/opt/spark/work-dir/spark_job.py -n $(NAMESPACE)
	$(KUBECTL) cp spark/model_utils.py spark-client-0:/opt/spark/work-dir/model_utils.py -n $(NAMESPACE)
	$(KUBECTL) cp spark/pretrained_models/ spark-client-0:/opt/spark/work-dir/pretrained_models/ -n $(NAMESPACE)
	$(KUBECTL) cp spark/spark_submit.sh spark-client-0:/opt/spark/work-dir/spark_submit.sh -n $(NAMESPACE)
	@echo "✅ Pipeline ready to process data"

# Soumettre un job Spark
submit-spark-job:
	@echo "🚀 Submitting Spark job..."
	$(KUBECTL) exec -it spark-client-0 -n $(NAMESPACE) -- /bin/bash /opt/spark/work-dir/spark_submit.sh

# Afficher les informations de monitoring
monitoring-info:
	@echo ""
	@echo "📊 Monitoring Access Information:"
	@echo "=================================="
	@echo "Prometheus: http://$(shell $(MINIKUBE) ip):30090"
	@echo "Grafana: http://$(shell $(MINIKUBE) ip):30030"
	@echo "  Username: admin"
	@echo "  Password: admin123"
	@echo ""
	@echo "Spark Master UI: http://$(shell $(MINIKUBE) ip):$(shell $(KUBECTL) get svc spark-master -n $(NAMESPACE) -o jsonpath='{.spec.ports[?(@.name=="webui")].nodePort}')"
	@echo ""

# Vérifier le statut du cluster
status:
	@echo "📊 Cluster Status:"
	@echo "=================="
	$(KUBECTL) get all -n $(NAMESPACE)
	@echo ""
	@echo "📈 Pod Resource Usage:"
	$(KUBECTL) top pods -n $(NAMESPACE) 2>/dev/null || echo "Metrics not available yet"

# Voir les logs du producer
logs-producer:
	$(KUBECTL) logs -l app=python-producer -n $(NAMESPACE) -f

# Voir les logs de Spark
logs-spark:
	$(KUBECTL) logs -l app=spark-client -n $(NAMESPACE) -f

# Voir les logs de Kafka
logs-kafka:
	$(KUBECTL) logs -l app=kafka-broker -n $(NAMESPACE) --tail=100

# Créer un topic Kafka manuellement
create-topic:
	@echo "📝 Creating Kafka topic 'demo'..."
	$(KUBECTL) exec -it kafka-broker-0 -n $(NAMESPACE) -- /opt/kafka/bin/kafka-topics.sh \
		--create --topic demo \
		--bootstrap-server kafka-broker-0.kafka-broker:19092 \
		--partitions 3 \
		--replication-factor 1

# Lister les topics Kafka
list-topics:
	@echo "📋 Kafka topics:"
	$(KUBECTL) exec -it kafka-broker-0 -n $(NAMESPACE) -- /opt/kafka/bin/kafka-topics.sh \
		--list --bootstrap-server kafka-broker-0.kafka-broker:19092

# Consumer de test
test-consumer:
	@echo "🔍 Starting test consumer..."
	$(KUBECTL) exec -it kafka-broker-0 -n $(NAMESPACE) -- /opt/kafka/bin/kafka-console-consumer.sh \
		--bootstrap-server kafka-broker-0.kafka-broker:19092 \
		--topic demo \
		--from-beginning

# Port-forward pour accès local
port-forward:
	@echo "🔗 Setting up port forwarding..."
	@echo "Prometheus will be available at: http://localhost:9090"
	@echo "Grafana will be available at: http://localhost:3000"
	$(KUBECTL) port-forward -n $(NAMESPACE) svc/prometheus 9090:9090 &
	$(KUBECTL) port-forward -n $(NAMESPACE) svc/grafana 3000:3000 &

# Arrêter le pipeline
stop-pipeline:
	@echo "⏹️ Stopping pipeline..."
	$(KUBECTL) scale deployment python-producer --replicas=0 -n $(NAMESPACE)
	@echo "✅ Pipeline stopped"

# Redémarrer le pipeline
restart-pipeline:
	@echo "🔄 Restarting pipeline..."
	$(KUBECTL) scale deployment python-producer --replicas=0 -n $(NAMESPACE)
	sleep 5
	$(KUBECTL) scale deployment python-producer --replicas=1 -n $(NAMESPACE)
	@echo "✅ Pipeline restarted"

# Nettoyer les ressources
clean-all:
	@echo "🧹 Cleaning all resources..."
	$(KUBECTL) delete namespace $(NAMESPACE) --ignore-not-found=true
	@echo "✅ All resources cleaned"

# Arrêter Minikube
stop-minikube:
	@echo "⏹️ Stopping Minikube..."
	$(MINIKUBE) stop

# Supprimer Minikube
delete-minikube:
	@echo "🗑️ Deleting Minikube..."
	$(MINIKUBE) delete

# Aide
help:
	@echo "📚 Available commands:"
	@echo "====================="
	@echo "  make all              - Start everything (Minikube + deploy + pipeline)"
	@echo "  make start-minikube   - Start Minikube cluster"
	@echo "  make deploy-all       - Deploy all components"
	@echo "  make start-pipeline   - Start the data processing pipeline"
	@echo "  make submit-spark-job - Submit Spark streaming job"
	@echo "  make status          - Show cluster status"
	@echo "  make monitoring-info - Show monitoring URLs"
	@echo "  make logs-producer   - Show producer logs"
	@echo "  make logs-spark      - Show Spark logs"
	@echo "  make logs-kafka      - Show Kafka logs"
	@echo "  make test-consumer   - Start a test Kafka consumer"
	@echo "  make port-forward    - Setup local port forwarding"
	@echo "  make stop-pipeline   - Stop the pipeline"
	@echo "  make restart-pipeline - Restart the pipeline"
	@echo "  make clean-all       - Clean all resources"
	@echo "  make stop-minikube   - Stop Minikube"
	@echo "  make help            - Show this help message"