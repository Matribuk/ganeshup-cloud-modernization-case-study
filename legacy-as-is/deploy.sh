#!/bin/bash

# Charger le .env pour DOMAIN_NAME
if [ -f "$(dirname "$0")/.env" ]; then
    set -a
    source "$(dirname "$0")/.env"
    set +a
fi
DOMAIN_NAME="${DOMAIN_NAME:-api.example.com}"

# Couleurs pour les logs
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Ganeshup Backend - Déploiement Auto  ${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# 1. Git Pull
echo -e "${YELLOW}[1/6]${NC} Git pull..."
git pull
if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Erreur lors du git pull${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Git pull réussi${NC}"
echo ""

# 1.5. Pre-deploy DB snapshot (point-in-time recovery just before any migration).
# The cron at 05:00 already gives us a 24h-max recovery window, but a deploy
# that ships a Prisma migration mutates the schema NOW — so capture the
# pre-migration state right here before docker rebuilds and entrypoint.sh
# applies `prisma migrate deploy`.
#
# We do an INLINE pg_dump instead of calling daily-backup.sh because the
# latter writes to /var/log/ganeshup/ (root-owned) and would fail when the
# deploy is run as the `ubuntu` user. The cron under root keeps doing the
# rotated/classified backups; this one just adds a "right before deploy"
# snapshot in backups/daily/ that the cron will rotate normally.
echo -e "${YELLOW}[2/6]${NC} Pre-deploy DB snapshot..."
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SNAPSHOT_DIR="$SCRIPT_DIR/backups/daily"
SNAPSHOT_NAME="ganeshup_db_predeploy_$(date '+%Y-%m-%d_%H-%M-%S').sql.gz"
SNAPSHOT_PATH="$SNAPSHOT_DIR/$SNAPSHOT_NAME"

mkdir -p "$SNAPSHOT_DIR"

if docker inspect ganeshup-postgres > /dev/null 2>&1 && \
   docker inspect --format='{{.State.Running}}' ganeshup-postgres | grep -q true; then
    if docker exec ganeshup-postgres pg_dump -U "${POSTGRES_USER:-ganeshup_user}" "${POSTGRES_DB:-ganeshup_db}" 2>/dev/null | gzip > "$SNAPSHOT_PATH"; then
        SNAPSHOT_SIZE=$(du -h "$SNAPSHOT_PATH" | cut -f1)
        chmod 600 "$SNAPSHOT_PATH" 2>/dev/null || true
        echo -e "${GREEN}✅ Snapshot DB créé : $SNAPSHOT_NAME ($SNAPSHOT_SIZE)${NC}"
    else
        echo -e "${RED}❌ pg_dump échoué — abort du deploy${NC}"
        rm -f "$SNAPSHOT_PATH"
        exit 1
    fi
else
    echo -e "${YELLOW}⚠️  Container postgres pas en cours — premier deploy ? (skip snapshot)${NC}"
fi
echo ""

# 2. Docker compose build avec le commit SHA injecté pour le release tag Sentry
GIT_COMMIT_SHA=$(git rev-parse HEAD)
echo -e "${YELLOW}[3/6]${NC} Docker compose build backend (release: ${GIT_COMMIT_SHA:0:7})..."
docker compose build --build-arg GIT_COMMIT_SHA="$GIT_COMMIT_SHA" backend
if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Erreur lors du docker build${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Docker build réussi${NC}"
echo ""

# 2.5 Ensure legal/ is writable by container user (nodejs uid 1001)
mkdir -p legal/backups
chown -R 1001:1001 legal/ 2>/dev/null || true
# chmod only directories (755) - do NOT chmod files to avoid git tracking mode changes
find legal/ -type d -exec chmod 755 {} \;

# 3. Docker compose up
echo -e "${YELLOW}[4/6]${NC} Redémarrage du container backend..."
docker compose up -d backend
if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Erreur lors du redémarrage${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Container redémarré${NC}"
echo ""

# 3.5 Ensure TLS auto-renewal stays provisioned (idempotent).
# certbot renouvelle en webroot (sans jamais stopper nginx) et un deploy-hook
# recopie le cert dans nginx/ssl + reload. Ce bloc recrée ce câblage à chaque
# deploy pour qu'un VPS reconstruit ne perde pas le renouvellement auto en
# silence. Il NE fait JAMAIS échouer le deploy (warn-only).
# Bootstrap initial du cert (certbot certonly --webroot) = one-shot manuel,
# non automatisable ici (DNS + validation). Voir mémoire project_tls_renewal.
echo -e "${YELLOW}[TLS]${NC} Vérification du pipeline de renouvellement TLS..."
WEBROOT="$SCRIPT_DIR/nginx/certbot-webroot"
SSL_DIR="$SCRIPT_DIR/nginx/ssl"
HOOK=/etc/letsencrypt/renewal-hooks/deploy/copy-to-nginx.sh
RENEWAL_CONF="/etc/letsencrypt/renewal/${DOMAIN_NAME}.conf"

# (a) webroot dir pour le challenge ACME HTTP-01 (bind-mount dans nginx)
mkdir -p "$WEBROOT/.well-known/acme-challenge" 2>/dev/null \
    && echo -e "${GREEN}✅ webroot ACME présent${NC}" \
    || echo -e "${YELLOW}⚠️  webroot ACME non créé${NC}"

# (b) deploy-hook : copie le cert renouvelé dans nginx/ssl + reload nginx
if sudo -n true 2>/dev/null; then
    sudo mkdir -p /etc/letsencrypt/renewal-hooks/deploy
    sudo tee "$HOOK" > /dev/null <<HOOK_EOF
#!/bin/sh
# Auto-généré par deploy.sh — copie le cert renouvelé vers nginx/ssl + reload.
set -e
DEST=$SSL_DIR
LIVE=/etc/letsencrypt/live/$DOMAIN_NAME
cp "\$LIVE/fullchain.pem" "\$DEST/fullchain.pem"
cp "\$LIVE/privkey.pem"   "\$DEST/privkey.pem"
chmod 644 "\$DEST/fullchain.pem"
docker exec ganeshup-nginx nginx -s reload
HOOK_EOF
    sudo chmod +x "$HOOK"
    echo -e "${GREEN}✅ deploy-hook TLS en place${NC}"

    # (c) check authenticator = webroot (warn-only, pas de réécriture auto)
    if sudo grep -q "authenticator = webroot" "$RENEWAL_CONF" 2>/dev/null; then
        echo -e "${GREEN}✅ certbot en mode webroot${NC}"
    elif sudo test -f "$RENEWAL_CONF" 2>/dev/null; then
        echo -e "${RED}⚠️  certbot PAS en webroot — renouvellement auto à risque (voir project_tls_renewal)${NC}"
    else
        echo -e "${YELLOW}⚠️  Aucun cert Let's Encrypt pour ${DOMAIN_NAME} — bootstrap initial requis (certbot certonly --webroot)${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  sudo indisponible — étapes TLS (deploy-hook) sautées${NC}"
fi

# (d) skip-worktree sur les .pem : les renouvellements ne dirty pas le git pull
git update-index --skip-worktree nginx/ssl/fullchain.pem nginx/ssl/privkey.pem 2>/dev/null \
    && echo -e "${GREEN}✅ skip-worktree sur les certs${NC}" \
    || echo -e "${YELLOW}⚠️  skip-worktree non appliqué (pems pas trackés ?)${NC}"
echo ""

# 4. Force recreate nginx to pick up new config (bind-mounted, no build needed)
echo -e "${YELLOW}[5/6]${NC} Redémarrage forcé de nginx..."
docker compose up -d --force-recreate nginx
if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Erreur lors du rebuild nginx${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Nginx redémarré${NC}"
echo ""

# 5. Vérification
echo -e "${YELLOW}[6/6]${NC} Vérification du déploiement..."
sleep 5
docker ps | grep ganeshup-backend
echo ""
docker logs --tail 10 ganeshup-backend
echo ""

# Test API health via l'URL publique
echo -e "${YELLOW}Test API Health...${NC}"
HEALTH_CHECK=$(curl -s -o /dev/null -w "%{http_code}" https://${DOMAIN_NAME}/ganeshup/api/health)
if [ "$HEALTH_CHECK" = "200" ]; then
    echo -e "${GREEN}✅ API Health OK (HTTP 200)${NC}"
else
    echo -e "${RED}⚠️  API Health: HTTP $HEALTH_CHECK (vérifiez nginx)${NC}"
fi

echo ""

# 6. Housekeeping Docker — chaque `docker compose build` empile du cache et
# laisse des images dangling. Sans nettoyage ça avait atteint ~37 Go (cache
# 19 Go + images 18 Go). On élague APRÈS un deploy réussi, warn-only :
# - garde 2 Go de cache récent (rebuilds rapides), purge le reste
# - supprime uniquement les images dangling (untagged), jamais les actives
echo -e "${YELLOW}[clean]${NC} Nettoyage Docker (cache + images dangling)..."
docker builder prune -f --reserved-space 2GB > /dev/null 2>&1 \
    && echo -e "${GREEN}✅ build cache élagué (garde 2 Go)${NC}" \
    || echo -e "${YELLOW}⚠️  builder prune sauté${NC}"
docker image prune -f > /dev/null 2>&1 \
    && echo -e "${GREEN}✅ images dangling supprimées${NC}" \
    || echo -e "${YELLOW}⚠️  image prune sauté${NC}"
echo -e "${GREEN}   disque : $(df -h / | awk 'NR==2{print $5" utilisé, "$4" libre"}')${NC}"

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  ✅ Déploiement terminé !${NC}"
echo -e "${GREEN}========================================${NC}"
