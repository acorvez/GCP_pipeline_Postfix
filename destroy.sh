#!/bin/bash

# Script pour détruire l'infrastructure GitOps déployée sur GCP
# À utiliser avec précaution - cette action est irréversible

set -e

# Couleurs pour la sortie
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Configuration
PROJECT_ID=""

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
    log_info "Vérification des prérequis pour la destruction..."
    
    # Vérifier si terraform est installé
    if ! command -v terraform &> /dev/null; then
        log_error "Terraform n'est pas installé. Installez-le depuis https://www.terraform.io/downloads.html"
    fi
    
    # Vérifier si gcloud est installé
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud SDK n'est pas installé. Installez-le depuis https://cloud.google.com/sdk/docs/install"
    fi
    
    # Vérifier que le répertoire terraform existe
    if [ ! -d "terraform" ]; then
        log_error "Répertoire terraform non trouvé. Exécutez ce script depuis le même répertoire que celui où vous avez lancé deploy.sh."
    fi
    
    # Vérifier que les fichiers terraform existent
    if [ ! -f "terraform/terraform.tfstate" ]; then
        log_warn "Fichier terraform.tfstate non trouvé. Il est possible que l'infrastructure n'ait pas été déployée ou que le fichier d'état soit manquant."
        read -p "Voulez-vous continuer quand même? (o/n): " continue_anyway
        if [[ $continue_anyway != "o" && $continue_anyway != "O" ]]; then
            log_error "Destruction annulée par l'utilisateur."
        fi
    fi
    
    log_info "Prérequis vérifiés."
}

function setup_gcp() {
    log_info "Configuration de GCP..."
    
    # Demander l'ID du projet si non défini
    if [ -z "$PROJECT_ID" ]; then
        # Essayer de récupérer l'ID du projet à partir de terraform.tfvars
        if [ -f "terraform/terraform.tfvars" ]; then
            PROJECT_ID=$(grep 'project_id' terraform/terraform.tfvars | cut -d '"' -f 2)
        fi
        
        # Si toujours vide, demander à l'utilisateur
        if [ -z "$PROJECT_ID" ]; then
            read -p "Entrez votre ID de projet GCP: " PROJECT_ID
            if [ -z "$PROJECT_ID" ]; then
                log_error "L'ID de projet GCP est requis."
            fi
        else
            log_info "ID de projet GCP trouvé: ${PROJECT_ID}"
        fi
    fi
    
    # Se connecter à GCP
    gcloud auth login
    
    # Définir le projet par défaut
    gcloud config set project $PROJECT_ID
    
    log_info "Configuration GCP terminée."
}

function destroy_infrastructure() {
    log_info "Préparation de la destruction de l'infrastructure..."
    
    # Se déplacer dans le répertoire terraform
    cd terraform
    
    # Demander confirmation
    log_warn "ATTENTION: Cette action va détruire toute l'infrastructure déployée."
    log_warn "Toutes les VMs et données associées seront DÉFINITIVEMENT PERDUES."
    
    read -p "Êtes-vous ABSOLUMENT SÛR de vouloir détruire l'infrastructure? Tapez 'DÉTRUIRE' pour confirmer: " confirmation
    if [ "$confirmation" != "DÉTRUIRE" ]; then
        log_error "Destruction annulée. Confirmation incorrecte."
    fi
    
    # Initialiser Terraform si nécessaire
    log_info "Initialisation de Terraform..."
    terraform init
    
    # Planifier la destruction
    log_info "Planification de la destruction..."
    terraform plan -destroy -out=destroy.tfplan
    
    # Dernière chance d'annuler
    log_warn "DERNIÈRE CHANCE: Toutes les ressources listées ci-dessus seront détruites."
    read -p "Procéder à la destruction? (o/n): " final_confirm
    if [[ $final_confirm != "o" && $final_confirm != "O" ]]; then
        log_error "Destruction annulée par l'utilisateur."
    fi
    
    # Appliquer le plan de destruction
    log_info "Destruction des ressources GCP en cours..."
    terraform apply destroy.tfplan
    
    cd ..
    
    log_info "Destruction de l'infrastructure terminée avec succès."
}

function cleanup_local_files() {
    log_info "Nettoyage des fichiers locaux..."
    
    # Demander confirmation
    read -p "Souhaitez-vous également supprimer les fichiers de configuration locaux? (o/n): " cleanup_confirm
    if [[ $cleanup_confirm == "o" || $cleanup_confirm == "O" ]]; then
        # Sauvegarde des fichiers importants au cas où
        log_info "Création d'une sauvegarde des fichiers importants..."
        backup_dir="backup_$(date +%Y%m%d_%H%M%S)"
        mkdir -p $backup_dir
        
        # Copier les fichiers importants dans le backup
        cp -r terraform/terraform.tfstate* $backup_dir/ 2>/dev/null || true
        cp -r terraform/terraform.tfvars $backup_dir/ 2>/dev/null || true
        cp -r ansible/inventory.ini $backup_dir/ 2>/dev/null || true
        cp -r vpn/client.ovpn $backup_dir/ 2>/dev/null || true
        
        log_info "Sauvegarde créée dans le répertoire: $backup_dir"
        
        # Supprimer les fichiers générés
        log_info "Suppression des fichiers générés..."
        rm -f terraform/destroy.tfplan 2>/dev/null || true
        rm -f terraform/tfplan 2>/dev/null || true
        rm -f ansible/inventory.ini 2>/dev/null || true
        
        log_info "Nettoyage terminé."
    else
        log_info "Les fichiers de configuration locaux ont été conservés."
    fi
}

function print_summary() {
    log_info "Processus de destruction terminé!"
    echo ""
    echo -e "${GREEN}=== RÉSUMÉ DE LA DESTRUCTION ===${NC}"
    echo "Toutes les ressources suivantes ont été détruites :"
    echo " - VMs de l'infrastructure (GitLab, Jenkins, Postfix, Monitoring, OpenVPN)"
    echo " - Disques persistants associés"
    echo " - Ressources réseau (VPC, règles de pare-feu, etc.)"
    echo ""
    echo -e "${YELLOW}Notes importantes:${NC}"
    echo "1. Vérifiez dans la console GCP qu'aucune ressource non souhaitée ne subsiste"
    echo "2. Si vous avez créé des instances manuellement, celles-ci pourraient ne pas avoir été supprimées"
    echo "3. Les enregistrements DNS pointant vers ces ressources devront être mis à jour"
    echo ""
    
    if [ -d "$backup_dir" ]; then
        echo -e "${YELLOW}Sauvegarde:${NC}"
        echo "Les fichiers de configuration ont été sauvegardés dans: $backup_dir"
        echo "Conservez cette sauvegarde si vous prévoyez de redéployer l'infrastructure."
    fi
}

# Exécution principale
function main() {
    log_info "Début du processus de destruction de l'infrastructure GitOps..."
    
    check_prerequisites
    setup_gcp
    destroy_infrastructure
    cleanup_local_files
    print_summary
    
    log_info "Processus de destruction terminé."
}

# Exécuter le script
main
