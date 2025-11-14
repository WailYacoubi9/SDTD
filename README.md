# Pipeline de Traitement de Données Distribué - Infrastructure Kubernetes

## 📋 Description

Infrastructure Kubernetes optimisée pour un pipeline de traitement de données distribué utilisant :
- **Apache Kafka** (KRaft mode) pour le streaming de messages
- **Apache Spark** pour le traitement distribué et ML
- **Python Producer** pour l'ingestion de données UNSW-NB15
- **Prometheus & Grafana** pour le monitoring

## 🚀 Démarrage Rapide

### Méthode 1: Script Automatisé
```bash
# Démarrer le pipeline complet
./deploy.sh start

# Voir le statut
./deploy.sh status

# Arrêter le pipeline
./deploy.sh stop
```

### Méthode 2: Makefile
```bash
# Démarrer tout
make all

# Soumettre le job Spark
make submit-spark-job

# Voir les logs
make logs-producer
make logs-spark
```

## 📁 Structure du Projet

```
.
├── k8s-configs/
│   ├── 00-namespace.yaml           # Namespace et quotas
│   ├── 01-kafka-controller.yaml    # Kafka KRaft Controller
│   ├── 02-kafka-broker.yaml        # Kafka Brokers (2 replicas)
│   ├── 03-spark-master.yaml        # Spark Master
│   ├── 04-spark-worker.yaml        # Spark Workers avec HPA
│   ├── 05-spark-client.yaml        # Spark Client pour jobs
│   ├── 06-producer-deployment.yaml # Python Producer (Deployment)
│   ├── 07-prometheus.yaml          # Prometheus monitoring
│   ├── 08-grafana.yaml            # Grafana dashboards
│   └── 09-kafka-exporter.yaml     # Kafka metrics exporter
├── spark/
│   ├── spark_job.py                # Job Spark Streaming
│   ├── model_utils.py              # Utilitaires ML
│   └── pretrained_models/          # Modèles pré-entraînés
├── Makefile                        # Commandes de gestion
├── deploy.sh                       # Script de déploiement
└── README.md                       # Cette documentation
```

## 🔧 Configuration

### Resources Kubernetes

| Composant | CPU Request | Memory Request | CPU Limit | Memory Limit |
|-----------|-------------|----------------|-----------|--------------|
| Kafka Controller | 250m | 512Mi | 500m | 1Gi |
| Kafka Broker | 300m | 512Mi | 500m | 1Gi |
| Spark Master | 500m | 1Gi | 1000m | 2Gi |
| Spark Worker | 500m | 1Gi | 1000m | 2Gi |
| Python Producer | 250m | 512Mi | 500m | 1Gi |
| Prometheus | 250m | 512Mi | 500m | 1Gi |
| Grafana | 250m | 256Mi | 500m | 512Mi |

### Minikube Requirements
- **Memory**: 6GB minimum
- **CPUs**: 4 cores
- **Disk**: 20GB

## 📊 Monitoring

### Accès aux interfaces

Après le déploiement, accédez aux interfaces :

```bash
# Obtenir l'IP de Minikube
minikube ip

# URLs d'accès
Prometheus: http://<minikube-ip>:30090
Grafana: http://<minikube-ip>:30030
  User: admin
  Password: admin123

# Port-forwarding alternatif
make port-forward
# Puis accéder à :
# - Prometheus: http://localhost:9090
# - Grafana: http://localhost:3000
```

### Métriques Disponibles

- **Kafka**: Messages/sec, Consumer lag, Partition distribution
- **Spark**: Active jobs, Executor memory, Task duration
- **System**: CPU/Memory usage, Pod health

## 🛠️ Opérations

### Gestion du Pipeline

```bash
# Voir les topics Kafka
make list-topics

# Créer un topic manuel
make create-topic

# Test consumer
make test-consumer

# Redémarrer le producer
make restart-pipeline

# Voir les logs
kubectl logs -f -l app=python-producer -n data-pipeline
kubectl logs -f -l app=spark-client -n data-pipeline
```

### Scaling

```bash
# Scale Spark Workers
kubectl scale deployment spark-worker --replicas=3 -n data-pipeline

# Scale Producer
kubectl scale deployment python-producer --replicas=2 -n data-pipeline
```

### Debugging

```bash
# Accès shell aux pods
kubectl exec -it kafka-broker-0 -n data-pipeline -- bash
kubectl exec -it spark-client-0 -n data-pipeline -- bash

# Vérifier l'état des pods
kubectl describe pod <pod-name> -n data-pipeline

# Voir les événements
kubectl get events -n data-pipeline --sort-by='.lastTimestamp'
```

## 🔍 Améliorations Apportées

1. **Organisation**: Namespace dédié avec quotas de ressources
2. **Producer en Deployment**: Meilleure gestion et scaling
3. **Health Checks**: Liveness et Readiness probes sur tous les services
4. **Auto-scaling**: HPA pour les Spark Workers
5. **Monitoring Complet**: Prometheus + Grafana avec dashboards
6. **ConfigMaps**: Scripts externalisés pour faciliter les mises à jour
7. **Resource Management**: Limites et requêtes optimisées
8. **Persistance**: PVC pour Kafka et Spark
9. **Automatisation**: Makefile et script de déploiement

## 📝 Notes Importantes

- Les données UNSW-NB15 sont téléchargées automatiquement par le producer
- Le modèle ML détecte les anomalies réseau en temps réel
- Les métriques sont collectées toutes les 15 secondes
- Les logs Kafka sont conservés 24h par défaut

## 🚨 Troubleshooting

### Pods en CrashLoopBackOff
```bash
# Vérifier les logs
kubectl logs <pod-name> -n data-pipeline --previous

# Augmenter les ressources si nécessaire
minikube stop
minikube start --memory=8192 --cpus=6
```

### Kafka Connection Issues
```bash
# Vérifier la connectivité
kubectl exec -it kafka-broker-0 -n data-pipeline -- \
  kcat -b localhost:19092 -L
```

### Spark Job Failures
```bash
# Vérifier les logs du driver
kubectl logs spark-client-0 -n data-pipeline

# UI Spark Master
kubectl port-forward svc/spark-master 8080:8080 -n data-pipeline
```

## 📚 Ressources

- [Apache Kafka Documentation](https://kafka.apache.org/documentation/)
- [Apache Spark Documentation](https://spark.apache.org/docs/latest/)
- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)

## ✅ Checklist de Déploiement

- [ ] Minikube démarré avec ressources suffisantes
- [ ] Namespace créé
- [ ] Kafka déployé et fonctionnel
- [ ] Spark cluster opérationnel
- [ ] Producer démarré
- [ ] Monitoring accessible
- [ ] Job Spark soumis
- [ ] Métriques visibles dans Grafana

## 📧 Support

Pour toute question sur l'infrastructure Kubernetes, contactez l'équipe DevOps.