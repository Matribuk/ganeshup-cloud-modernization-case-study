#!/bin/bash

# =============================================================
#   Ganeshup Backend - VPS Setup Script
#   Use this once on a fresh VPS to get everything running.
#   For subsequent deployments, use ./deploy.sh
#
#   PREREQUISITES (before running this script):
#   1. Clone the repo: git clone <repo-url> && cd backend
#   2. Install Docker: https://docs.docker.com/engine/install/
#   3. Install Docker Compose V2 (included in Docker >= 20.10)
#   4. Generate SSL certificates (Let's Encrypt recommended)
#   5. Create .env file with all required variables
# =============================================================

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}   Ganeshup Backend - Setup VPS          ${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "ℹ️  Ce script configure un VPS NEUF."
echo "   Pour les déploiements ultérieurs, utilisez: ./deploy.sh"
echo ""

# -------------------------------------------------------
# 1. Prerequisites
# -------------------------------------------------------
echo -e "${YELLOW}[1/7]${NC} Vérification des prérequis..."

if ! command -v docker &>/dev/null; then
    echo -e "${RED}❌ Docker n'est pas installé.${NC}"
    echo "   Installez Docker : https://docs.docker.com/engine/install/"
    exit 1
fi

if ! docker compose version &>/dev/null; then
    echo -e "${RED}❌ Docker Compose V2 n'est pas disponible.${NC}"
    echo "   Mettez Docker à jour (>= 20.10) ou installez le plugin compose."
    exit 1
fi

if ! command -v git &>/dev/null; then
    echo -e "${RED}❌ Git n'est pas installé.${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Docker $(docker --version | awk '{print $3}' | tr -d ','), Docker Compose V2, Git OK${NC}"
echo ""

# -------------------------------------------------------
# 2. .env file
# -------------------------------------------------------
echo -e "${YELLOW}[2/7]${NC} Vérification du fichier .env..."

REQUIRED_VARS=(
    POSTGRES_PASSWORD
    JWT_SECRET
    API_KEY
    ADMIN_TOKEN
    ENCRYPTION_KEY
    OWNER_TOKEN
    DOMAIN_NAME
)

if [ ! -f .env ]; then
    echo -e "${RED}❌ Fichier .env manquant.${NC}"
    echo ""
    echo "   Créez un fichier .env avec les variables suivantes :"
    for var in "${REQUIRED_VARS[@]}"; do
        echo "   $var="
    done
    echo ""
    echo "   Exemple rapide : nano .env"
    exit 1
fi

MISSING=()
for var in "${REQUIRED_VARS[@]}"; do
    if ! grep -q "^${var}=" .env || [ -z "$(grep "^${var}=" .env | cut -d'=' -f2-)" ]; then
        MISSING+=("$var")
    fi
done

if [ ${#MISSING[@]} -ne 0 ]; then
    echo -e "${RED}❌ Variables manquantes dans .env :${NC}"
    for var in "${MISSING[@]}"; do
        echo "   - $var"
    done
    exit 1
fi

echo -e "${GREEN}✅ .env OK${NC}"
echo ""

# -------------------------------------------------------
# 3. SSL certificates
# -------------------------------------------------------
echo -e "${YELLOW}[3/7]${NC} Vérification des certificats SSL..."

if [ ! -f nginx/ssl/fullchain.pem ] || [ ! -f nginx/ssl/privkey.pem ]; then
    echo -e "${RED}❌ Certificats SSL manquants dans nginx/ssl/${NC}"
    echo ""
    DOMAIN=$(grep "^DOMAIN_NAME=" .env | cut -d'=' -f2-)
    echo "   Générez des certificats Let's Encrypt :"
    echo "   sudo apt install certbot"
    echo "   sudo certbot certonly --standalone -d ${DOMAIN:-votre-domaine.com}"
    echo "   sudo mkdir -p nginx/ssl"
    echo "   sudo cp /etc/letsencrypt/live/${DOMAIN:-votre-domaine.com}/fullchain.pem nginx/ssl/"
    echo "   sudo cp /etc/letsencrypt/live/${DOMAIN:-votre-domaine.com}/privkey.pem nginx/ssl/"
    echo "   sudo chown \$(whoami):\$(whoami) nginx/ssl/*.pem"
    exit 1
fi

echo -e "${GREEN}✅ Certificats SSL OK${NC}"
echo ""

# -------------------------------------------------------
# 4. Permissions legal/ (nodejs uid 1001 doit pouvoir écrire)
# -------------------------------------------------------
echo -e "${YELLOW}[4/7]${NC} Permissions du dossier legal/..."

mkdir -p legal/backups
chown -R 1001:1001 legal/ 2>/dev/null || true
find legal/ -type d -exec chmod 755 {} \;

echo -e "${GREEN}✅ Permissions legal/ OK (uid 1001)${NC}"
echo ""

# -------------------------------------------------------
# 5. Permissions scripts
# -------------------------------------------------------
echo -e "${YELLOW}[5/7]${NC} Permissions des scripts..."

chmod +x deploy.sh quick-restart.sh logs.sh entrypoint.sh 2>/dev/null || true

echo -e "${GREEN}✅ Scripts exécutables${NC}"
echo ""

# -------------------------------------------------------
# 6. Build + Start all services
# -------------------------------------------------------
echo -e "${YELLOW}[6/7]${NC} Build et démarrage des containers..."

docker compose build backend
if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Erreur lors du build${NC}"
    exit 1
fi

docker compose up -d
if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Erreur lors du démarrage${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Containers démarrés (postgres, redis, backend, nginx)${NC}"
echo ""

# -------------------------------------------------------
# 7. Health check
# -------------------------------------------------------
echo -e "${YELLOW}[7/7]${NC} Vérification de santé (attente 15s)..."
sleep 15

docker ps | grep -E "ganeshup-(backend|nginx|postgres|redis)"
echo ""

DOMAIN=$(grep "^DOMAIN_NAME=" .env | cut -d'=' -f2-)
HEALTH=$(curl -s -o /dev/null -w "%{http_code}" "https://${DOMAIN}/ganeshup/api/health" 2>/dev/null || echo "000")

if [ "$HEALTH" = "200" ]; then
    echo -e "${GREEN}✅ API Health OK (HTTP 200)${NC}"
else
    echo -e "${YELLOW}⚠️  API Health: HTTP $HEALTH${NC}"
    echo "   Vérifiez les logs : docker logs --tail 30 ganeshup-backend"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  ✅ Setup terminé !                    ${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "📋 Commandes utiles :"
echo "   ./deploy.sh          → déploiement complet (après git pull)"
echo "   ./quick-restart.sh   → restart rapide (fichiers statiques)"
echo "   ./logs.sh -f         → logs en temps réel"
echo "   docker ps            → état des containers"
echo ""
