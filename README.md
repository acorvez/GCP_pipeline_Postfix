# Infrastructure GitOps complète sur GCP

Ce projet constitue un portfolio GitOps complet avec une infrastructure hébergée sur Google Cloud Platform (GCP). Il déploie un ensemble de services essentiels pour une CI/CD moderne et une gestion d'applications, accessible via VPN pour plus de sécurité.

## Architecture

L'infrastructure mise en place comprend :

- **Réseau sécurisé** : Un VPC dédié avec des règles de pare-feu appropriées
- **Accès sécurisé** : Serveur OpenVPN pour un accès privé à l'infrastructure
- **CI/CD** : Pipeline Jenkins pour l'automatisation des builds et déploiements
- **Gestion de code** : GitLab pour le stockage et la gestion des configurations et du code
- **Services de messagerie** : Postfix conteneurisé avec PostgreSQL pour la persistance des données
- **Monitoring** : Suite de surveillance Prometheus/Grafana pour la supervision de toute l'infrastructure

## Composants

1. **Infrastructure as Code** :
   - Terraform pour provisionner les ressources GCP
   - Ansible pour configurer les serveurs et déployer les applications

2. **Conteneurisation** :
   - Docker pour exécuter les applications dans des conteneurs isolés
   - Docker Compose pour orchestrer les conteneurs

3. **CI/CD** :
   - Jenkins pour l'intégration et le déploiement continus
   - Pipelines automatisés pour le build, test et déploiement

4. **Monitoring** :
   - Prometheus pour la collecte de métriques
   - Grafana pour la visualisation et les alertes
   - NodeExporter et cAdvisor pour les métriques système

## Prérequis

- Compte GCP avec facturation activée
- gcloud CLI installé et configuré
- Terraform v1.0.0+
- Ansible v2.9+
- Docker et Docker Compose
- Une paire de clés SSH

## Déploiement

Le déploiement complet est automatisé via un script bash :

```bash
chmod +x deploy.sh
./deploy.sh
```

Le script réalise les opérations suivantes :
1. Vérification des prérequis
2. Configuration de GCP
3. Déploiement de l'infrastructure avec Terraform
4. Configuration des serveurs avec Ansible
5. Téléchargement de la configuration VPN

## Accès aux services

Une fois déployés, les services sont accessibles :

- **Jenkins** : http://JENKINS_IP:8080
- **GitLab** : https://GITLAB_IP
- **Postfix** : https://mail.example.com
- **PGAdmin** : https://pgadmin.example.com
- **Grafana** : http://MONITORING_IP:3000

> **Note** : Vous devez d'abord vous connecter au VPN pour accéder à ces services en toute sécurité.

## Personnalisation

Pour adapter ce projet à vos besoins :

1. Modifiez `terraform.tfvars` pour ajuster les paramètres GCP
2. Personnalisez les templates Ansible dans le répertoire `roles/*/templates/`
3. Mettez à jour les fichiers Docker Compose pour les services conteneurisés
4. Adaptez les pipelines Jenkins selon vos workflows

## Maintenance

Quelques commandes utiles pour la maintenance :

- **Mise à jour de l'infrastructure** : `terraform apply`
- **Reconfiguration des applications** : `ansible-playbook -i inventory.ini site.yml`
- **Visualisation des journaux** : `ssh admin@SERVICE_IP "docker-compose logs -f"`

## Sécurité

Cette infrastructure implémente plusieurs niveaux de sécurité :
- Accès uniquement via VPN
- Pare-feu restrictif
- HTTPS pour les services exposés
- Isolation des services via des conteneurs Docker
- Volumes persistants pour les données critiques

## Contribution

N'hésitez pas à contribuer à ce projet en soumettant des issues ou des pull requests.

## Licence

Ce projet est distribué sous licence MIT. Voir le fichier `LICENSE` pour plus de détails.
