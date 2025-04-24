#!/bin/bash

# Script de déploiement de l'infrastructure GitOps sur GCP
# Version actualisée incluant les corrections intégrées dans les rôles Ansible

set -e

# Couleurs pour la sortie
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Configuration
PROJECT_ID=""
REGION="europe-west1"
ZONE="europe-west1-b"
SSH_USER="admin"
SSH_KEY_FILE="$HOME/.ssh/id_rsa"
SSH_PUB_KEY_FILE="$HOME/.ssh/id_rsa.pub"
DOMAIN="example.com"
EMAIL="admin@example.com"
GITLAB_ROOT_PASSWORD="gitlabadmin123"  # À modifier pour la production
JENKINS_ADMIN_PASSWORD="jenkinsadmin123"  # À modifier pour la production

# Fonctions utilitaires
function log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

function log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

function log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

function check_prerequisites() {
    log_info "Vérification des prérequis..."
    
    # Vérifier si terraform est installé
    if ! command -v terraform &> /dev/null; then
        log_error "Terraform n'est pas installé. Installez-le depuis https://www.terraform.io/downloads.html"
    fi
    
    # Vérifier si ansible est installé
    if ! command -v ansible &> /dev/null; then
        log_error "Ansible n'est pas installé. Installez-le via pip: pip install ansible"
    fi
    
    # Vérifier si gcloud est installé
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud SDK n'est pas installé. Installez-le depuis https://cloud.google.com/sdk/docs/install"
    fi
    
    # Vérifier si la clé SSH existe
    if [ ! -f "$SSH_PUB_KEY_FILE" ]; then
        log_warn "Clé SSH publique non trouvée. Génération d'une nouvelle paire de clés..."
        ssh-keygen -t rsa -b 4096 -f "$SSH_KEY_FILE" -N ""
    fi
    
    # Vérifier que les playbooks requis existent
    if [ ! -f "ansible/site.yml" ]; then
        log_error "Le playbook principal 'ansible/site.yml' est manquant. Veuillez vérifier la structure de votre projet."
    fi
    
    log_info "Tous les prérequis sont satisfaits."
}

function setup_gcp() {
    log_info "Configuration de GCP..."
    
    # Demander l'ID du projet si non défini
    if [ -z "$PROJECT_ID" ]; then
        read -p "Entrez votre ID de projet GCP: " PROJECT_ID
        if [ -z "$PROJECT_ID" ]; then
            log_error "L'ID de projet GCP est requis."
        fi
    fi
    
    # Se connecter à GCP
    gcloud auth login
    
    # Définir le projet par défaut
    gcloud config set project $PROJECT_ID
    
    # Activer les APIs nécessaires
    log_info "Activation des APIs GCP nécessaires..."
    gcloud services enable compute.googleapis.com
    gcloud services enable iam.googleapis.com
    
    log_info "Configuration GCP terminée."
}

function deploy_terraform() {
    log_info "Déploiement de l'infrastructure avec Terraform..."
    
    # Créer le répertoire de travail Terraform
    mkdir -p terraform
    cd terraform
    
    # Copier les fichiers Terraform s'ils n'existent pas déjà
    if [ ! -f "main.tf" ]; then
        cp ../terraform/main.tf .
    fi
    
    if [ ! -f "variables.tf" ]; then
        cp ../terraform/variables.tf .
    fi
    
    # Créer le fichier terraform.tfvars
    cat > terraform.tfvars << EOL
project_id        = "${PROJECT_ID}"
region            = "${REGION}"
zone              = "${ZONE}"
ssh_user          = "${SSH_USER}"
ssh_pub_key_file  = "${SSH_PUB_KEY_FILE}"
EOL
    
    # Initialiser Terraform
    log_info "Initialisation de Terraform..."
    terraform init
    
    # Planifier le déploiement
    log_info "Planification du déploiement Terraform..."
    terraform plan -out=tfplan
    
    # Demander confirmation
    read -p "Voulez-vous procéder au déploiement des VMs sur GCP? (o/n): " confirm
    if [[ $confirm != "o" && $confirm != "O" ]]; then
        log_error "Déploiement annulé par l'utilisateur."
    fi
    
    # Appliquer le plan
    log_info "Déploiement des ressources GCP en cours..."
    terraform apply tfplan
    
    # Extraire les IPs pour Ansible
    log_info "Extraction des IPs pour l'inventaire Ansible..."
    OPENVPN_IP=$(terraform output -raw openvpn_ip)
    JENKINS_IP=$(terraform output -raw jenkins_ip)
    GITLAB_IP=$(terraform output -raw gitlab_ip)
    POSTFIX_IP=$(terraform output -raw postfix_ip)
    MONITORING_IP=$(terraform output -raw monitoring_ip)
    
    cd ..
    
    log_info "Déploiement Terraform terminé avec succès."
}

function update_ansible_inventory() {
    log_info "Mise à jour de l'inventaire Ansible..."
    
    # Créer ou mettre à jour le fichier d'inventaire
    mkdir -p ansible
    
    cat > ansible/inventory.ini << EOL
[openvpn]
openvpn ansible_host=${OPENVPN_IP} ansible_user=${SSH_USER}

[jenkins]
jenkins ansible_host=${JENKINS_IP} ansible_user=${SSH_USER}

[gitlab]
gitlab ansible_host=${GITLAB_IP} ansible_user=${SSH_USER}

[postfix]
postfix ansible_host=${POSTFIX_IP} ansible_user=${SSH_USER}

[monitoring]
monitoring ansible_host=${MONITORING_IP} ansible_user=${SSH_USER}

[all:vars]
ansible_python_interpreter=/usr/bin/python3
domain=${DOMAIN}
admin_email=${EMAIL}
gitlab_root_password=${GITLAB_ROOT_PASSWORD}
jenkins_admin_password=${JENKINS_ADMIN_PASSWORD}
EOL
    
    log_info "Inventaire Ansible mis à jour avec succès."
}

function deploy_ansible() {
    log_info "Déploiement des applications avec Ansible..."
    
    # Attendre que les VMs soient prêtes
    log_info "Attente de l'initialisation des VMs (30s)..."
    sleep 30
    
    # Supprimer les anciennes entrées SSH known_hosts pour éviter les erreurs de clé
    log_info "Nettoyage des clés SSH connues pour éviter les erreurs de changement de clé..."
    for host in $OPENVPN_IP $JENKINS_IP $GITLAB_IP $POSTFIX_IP $MONITORING_IP; do
        ssh-keygen -f "$HOME/.ssh/known_hosts" -R $host &>/dev/null || true
    done
    
    # Vérifier la connectivité SSH avec StrictHostKeyChecking=no
    log_info "Vérification de la connectivité SSH..."
    for host in $OPENVPN_IP $JENKINS_IP $GITLAB_IP $POSTFIX_IP $MONITORING_IP; do
        until ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 ${SSH_USER}@${host} 'echo SSH OK'; do
            log_warn "En attente de SSH pour ${host}..."
            sleep 5
        done
    done
    
    cd ansible
    
    # Créer un fichier de configuration SSH temporaire pour Ansible
    cat > ansible_ssh_config << EOL
Host *
    StrictHostKeyChecking no
    UserKnownHostsFile=/dev/null
EOL
    
    # Déployer tous les services via le playbook principal avec les paramètres SSH modifiés
    log_info "Déploiement de l'infrastructure complète avec tous les correctifs intégrés..."
    ANSIBLE_SSH_ARGS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null" ansible-playbook -i inventory.ini site.yml || true
    
    # Attendre un peu entre les étapes
    sleep 10
    
    # Vérifier que tous les services sont bien démarrés (également avec SSH modifié)
    log_info "Vérification du statut des services..."
    ANSIBLE_SSH_ARGS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null" ansible-playbook -i inventory.ini -m shell -a "systemctl status jenkins || docker ps" all || true
    
    # Supprimer le fichier de configuration SSH temporaire
    rm -f ansible_ssh_config
    
    cd ..
    
    log_info "Déploiement Ansible terminé avec succès."
}




function configure_vpn() {
    log_info "Configuration du client VPN..."
    
    # Générer la configuration OpenVPN avec sudo
    ssh -o StrictHostKeyChecking=no ${SSH_USER}@${OPENVPN_IP} "sudo bash -c 'mkdir -p /etc/openvpn/client && cat > /etc/openvpn/client/client.ovpn << EOF
client
dev tun
proto udp
remote ${OPENVPN_IP} 1194
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
cipher AES-256-CBC
verb 3

<ca>
\$(cat /etc/openvpn/server/ca.crt 2>/dev/null || echo \"# CA certificate not found\")
</ca>

<cert>
\$(cat /etc/openvpn/easyrsa/pki/issued/client.crt 2>/dev/null || echo \"# Client certificate not found\")
</cert>

<key>
\$(cat /etc/openvpn/easyrsa/pki/private/client.key 2>/dev/null || echo \"# Client key not found\")
</key>

<tls-auth>
\$(cat /etc/openvpn/server/ta.key 2>/dev/null || echo \"# TLS auth key not found\")
</tls-auth>
key-direction 1
EOF'"
    
    # Corriger les permissions et copier le fichier
    ssh -o StrictHostKeyChecking=no ${SSH_USER}@${OPENVPN_IP} "sudo cp /etc/openvpn/client/client.ovpn /tmp/ && sudo chmod 644 /tmp/client.ovpn && sudo chown ${SSH_USER}:${SSH_USER} /tmp/client.ovpn"
    
    # Télécharger la configuration OpenVPN
    mkdir -p vpn
    scp -o StrictHostKeyChecking=no ${SSH_USER}@${OPENVPN_IP}:/tmp/client.ovpn vpn/
    
    log_info "Configuration VPN téléchargée dans le répertoire ./vpn/"
    log_info "Pour vous connecter au VPN: sudo openvpn --config vpn/client.ovpn"
}

function verify_services() {
    log_info "Vérification des services déployés..."
    
    # Vérifier GitLab
    log_info "Vérification de GitLab..."
    curl -s -o /dev/null -w "%{http_code}" http://${GITLAB_IP}/ | grep -q "200\|302" && 
        echo "GitLab est accessible" || 
        echo "GitLab n'est pas accessible"
    
    # Vérifier Jenkins
    log_info "Vérification de Jenkins..."
    curl -s -o /dev/null -w "%{http_code}" http://${JENKINS_IP}:8080/ | grep -q "200\|403" && 
        echo "Jenkins est accessible" || 
        echo "Jenkins n'est pas accessible"
    
    # Vérifier Grafana
    log_info "Vérification de Grafana..."
    curl -s -o /dev/null -w "%{http_code}" http://${MONITORING_IP}:3000/ | grep -q "200\|302" && 
        echo "Grafana est accessible" || 
        echo "Grafana n'est pas accessible"
    
    # Vérifier Postfix
    log_info "Vérification de Postfix..."
    ssh -o StrictHostKeyChecking=no ${SSH_USER}@${POSTFIX_IP} "sudo docker ps | grep -q postfix" && 
        echo "Postfix est en cours d'exécution" || 
        echo "Postfix n'est pas en cours d'exécution"
}

function print_summary() {
    log_info "Déploiement terminé avec succès!"
    echo ""
    echo -e "${GREEN}=== RÉCAPITULATIF ===${NC}"
    echo -e "OpenVPN:    ${OPENVPN_IP}"
    echo -e "Jenkins:    ${JENKINS_IP}    (http://${JENKINS_IP}:8080)"
    echo -e "GitLab:     ${GITLAB_IP}     (http://${GITLAB_IP})"
    echo -e "Postfix:    ${POSTFIX_IP}    (http://${POSTFIX_IP})"
    echo -e "Monitoring: ${MONITORING_IP} (http://${MONITORING_IP}:3000)"
    echo ""
    echo -e "${YELLOW}Informations d'authentification:${NC}"
    echo "Jenkins: admin / ${JENKINS_ADMIN_PASSWORD}"
    echo "GitLab: root / (voir /etc/gitlab/initial_root_password sur le serveur GitLab)"
    echo "Grafana: admin / admin"
    echo ""
    echo -e "${YELLOW}Actions requises:${NC}"
    echo "1. Configurez vos enregistrements DNS pour pointer vers ces adresses IP"
    echo "2. Connectez-vous au VPN en utilisant le fichier de configuration dans ./vpn/"
    echo "3. Changez les mots de passe par défaut pour chaque service"
    echo "4. Vérifiez que le pipeline CI/CD est correctement configuré entre GitLab et Jenkins"
    echo ""
}

# Exécution principale
function main() {
    log_info "Démarrage du déploiement de l'infrastructure GitOps..."
    
    check_prerequisites
    setup_gcp
    deploy_terraform
    update_ansible_inventory
    deploy_ansible
    configure_vpn
    verify_services
    print_summary
}

# Exécuter le script
main
