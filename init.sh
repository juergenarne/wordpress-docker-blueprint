#!/usr/bin/env bash
# Sets up a WordPress site from this blueprint on an Ubuntu server.
#
#   Docker, Apache/PHP and MariaDB data: /opt/wordpress/<domain>       (root)
#   WordPress files:                     /var/www/htdocs/<domain>      (www-data)
#   nginx relay config:                  /opt/wordpress/<domain>/nginx/<domain>.conf
#
# Usage: sudo ./init.sh

set -euo pipefail
shopt -s nullglob

BLUEPRINT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_BASE=/opt/wordpress
HTDOCS_BASE=/var/www/htdocs

die()  { echo "Fehler: $*" >&2; exit 1; }
info() { echo; echo "==> $*"; }

# ask <variable> <prompt> [default]
ask() {
  local __var=$1 __prompt=$2 __default=${3:-} __answer
  if [[ -n $__default ]]; then
    read -rp "$__prompt [$__default]: " __answer
  else
    read -rp "$__prompt: " __answer
  fi
  printf -v "$__var" '%s' "${__answer:-$__default}"
}

# ask_yes_no <prompt> <default y|n>
ask_yes_no() {
  local answer
  read -rp "$1 [$( [[ $2 == y ]] && echo J/n || echo j/N )]: " answer
  answer=${answer:-$2}
  [[ $answer =~ ^[jJyY] ]]
}

# random_string <length>: alphanumeric only, safe for .env and sed
random_string() {
  local s
  s=$(openssl rand -base64 $(( $1 * 2 )) | tr -dc 'A-Za-z0-9')
  echo "${s:0:$1}"
}

# set_env <key> <value>: replaces the key in .env or appends it
set_env() {
  if grep -q "^$1=" "$ENV_FILE"; then
    sed -i "s|^$1=.*|$1=$2|" "$ENV_FILE"
  else
    echo "$1=$2" >> "$ENV_FILE"
  fi
}

# free_port <start>: first port that is neither listening nor claimed by another site
free_port() {
  local port=$1
  while ss -Htln "sport = :$port" | grep -q . || grep -qx "$port" <<< "$USED_PORTS"; do
    port=$(( port + 1 ))
  done
  USED_PORTS+=$'\n'"$port"
  echo "$port"
}

wpcli() {
  docker compose exec -T -u www-data -e WP_CLI_CACHE_DIR=/tmp/wp-cli-cache web wp "$@"
}

# --- Checks -------------------------------------------------------------------

[[ $EUID -eq 0 ]] || die "Bitte als root ausführen: sudo ./init.sh"
command -v docker >/dev/null || die "Docker ist nicht installiert."
docker compose version >/dev/null 2>&1 || die "Das Docker-Compose-Plugin fehlt (docker compose)."
for cmd in openssl rsync ss; do
  command -v "$cmd" >/dev/null || die "'$cmd' ist nicht installiert."
done
id www-data >/dev/null 2>&1 || die "Der Benutzer www-data existiert nicht."

# --- Questions ----------------------------------------------------------------

echo "WordPress-Installation aus dem Blueprint $BLUEPRINT_DIR"
echo

ask DOMAIN "Domain (z.B. meine-domain.tld)"
DOMAIN=${DOMAIN,,}
DOMAIN=${DOMAIN#http://}
DOMAIN=${DOMAIN#https://}
DOMAIN=${DOMAIN%%/*}
DOMAIN=${DOMAIN#www.}
[[ $DOMAIN =~ ^([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z0-9-]{2,}$ ]] || die "Ungültige Domain: '$DOMAIN'"

SERVER_NAMES=$DOMAIN
CERTBOT_DOMAINS="-d $DOMAIN"
if ask_yes_no "Auch www.$DOMAIN ausliefern? (DNS-Eintrag muss existieren)" n; then
  SERVER_NAMES="$DOMAIN www.$DOMAIN"
  CERTBOT_DOMAINS="-d $DOMAIN -d www.$DOMAIN"
fi

TARGET_DIR=$INSTALL_BASE/$DOMAIN
HTDOCS_DIR=$HTDOCS_BASE/$DOMAIN
ENV_FILE=$TARGET_DIR/.env

[[ -e $ENV_FILE ]] && die "$ENV_FILE existiert bereits, $DOMAIN ist schon eingerichtet."
if [[ -d $HTDOCS_DIR ]] && [[ -n $(ls -A "$HTDOCS_DIR") ]]; then
  die "$HTDOCS_DIR existiert bereits und ist nicht leer."
fi

echo
ask WP_TITLE    "Titel der Website" "$DOMAIN"
ask WP_ADMIN    "WordPress-Admin-Benutzername"
[[ -n $WP_ADMIN && $WP_ADMIN != admin ]] || die "Bitte einen Admin-Namen angeben (nicht 'admin')."
ask WP_EMAIL    "E-Mail-Adresse des Admins"
[[ $WP_EMAIL =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]] || die "Ungültige E-Mail-Adresse: '$WP_EMAIL'"
ask WP_LOCALE   "Sprache" "de_DE"
ask WP_TIMEZONE "Zeitzone" "Europe/Berlin"

echo
echo "SMTP für den Mailversand (msmtp). Leer lassen, um es später in $TARGET_DIR/msmtprc einzutragen."
ask SMTP_HOST "SMTP-Server"
if [[ -n $SMTP_HOST ]]; then
  ask SMTP_PORT "SMTP-Port" "587"
  ask SMTP_USER "SMTP-Benutzer"
  read -rsp "SMTP-Passwort: " SMTP_PASSWORD; echo
  ask SMTP_FROM "Absenderadresse" "$SMTP_USER"
fi

# --- Docker project in /opt/wordpress/<domain> --------------------------------

info "Lege $TARGET_DIR an"
mkdir -p "$TARGET_DIR"
if [[ $BLUEPRINT_DIR != "$TARGET_DIR" ]]; then
  rsync -a --exclude=/src/ --exclude=/.env --exclude=/msmtprc --exclude=/mariadb/ \
    --exclude='/nginx/*.conf' --exclude=.DS_Store "$BLUEPRINT_DIR/" "$TARGET_DIR/"
fi
chown -R root:root "$TARGET_DIR"
chmod 750 "$TARGET_DIR"
cd "$TARGET_DIR"

# --- .env ---------------------------------------------------------------------

info "Erzeuge .env mit neuen Passwörtern und Keys"
USED_PORTS=$(cat "$INSTALL_BASE"/*/.env /dev/null | grep -E '^(APACHE|MYSQL)_PORT=' | cut -d= -f2 || true)
APACHE_PORT=$(free_port 8080)
MYSQL_PORT=$(free_port 3306)

cp .env.dist "$ENV_FILE"
chmod 600 "$ENV_FILE"

APP_NAME=$(tr -c 'a-z0-9\n' '-' <<< "$DOMAIN")
set_env APP_NAME               "$APP_NAME"
set_env COMPOSE_PROJECT_NAME   "$APP_NAME"
set_env BIND_ADDRESS           127.0.0.1
set_env APACHE_HTDOCS          "$HTDOCS_DIR"
set_env APACHE_PORT            "$APACHE_PORT"
set_env MYSQL_PORT             "$MYSQL_PORT"
set_env MYSQL_ROOT_PASSWORD    "$(random_string 32)"
set_env MYSQL_PASSWORD         "$(random_string 32)"
set_env WORDPRESS_URL          "https://$DOMAIN"
set_env WORDPRESS_TABLE_PREFIX "wp_$(random_string 6 | tr 'A-Z' 'a-z')_"
for key in AUTH_KEY SECURE_AUTH_KEY LOGGED_IN_KEY NONCE_KEY AUTH_SALT SECURE_AUTH_SALT LOGGED_IN_SALT NONCE_SALT; do
  set_env "WORDPRESS_$key" "$(random_string 64)"
done

# --- msmtp --------------------------------------------------------------------

info "Erzeuge msmtprc"
if [[ -n $SMTP_HOST ]]; then
  cat > msmtprc <<EOF
defaults
auth           on
tls            on
tls_trust_file /etc/ssl/certs/ca-certificates.crt
logfile        /var/log/msmtp.log

account default
host $SMTP_HOST
port $SMTP_PORT
from $SMTP_FROM
user $SMTP_USER
password $SMTP_PASSWORD
EOF
else
  cp msmtprc.dist msmtprc
  echo "    Platzhalter übernommen, bitte $TARGET_DIR/msmtprc anpassen."
fi
chmod 644 msmtprc

# --- WordPress files in /var/www/htdocs/<domain> -----------------------------

info "Kopiere WordPress nach $HTDOCS_DIR"
mkdir -p "$HTDOCS_DIR"
rsync -a --exclude=.DS_Store "$BLUEPRINT_DIR/src/htdocs/" "$HTDOCS_DIR/"
chown -R www-data:www-data "$HTDOCS_DIR"
find "$HTDOCS_DIR" -type d -exec chmod 755 {} +
find "$HTDOCS_DIR" -type f -exec chmod 644 {} +

# --- nginx relay --------------------------------------------------------------

info "Erzeuge nginx/$DOMAIN.conf"
sed -e "s|{{DOMAIN}}|$DOMAIN|g" \
    -e "s|{{SERVER_NAMES}}|$SERVER_NAMES|g" \
    -e "s|{{PORT}}|$APACHE_PORT|g" \
    nginx/site.conf.dist > "nginx/$DOMAIN.conf"

# --- Containers ---------------------------------------------------------------

info "Baue und starte die Container"
docker compose up -d --build

info "Warte auf die Datenbank"
for i in $(seq 1 60); do
  if docker compose exec -T web php -r '
      [$host, $port] = explode(":", getenv("WORDPRESS_DB_HOST")) + [1 => 3306];
      try { new mysqli($host, getenv("WORDPRESS_DB_USER"), getenv("WORDPRESS_DB_PASSWORD"), getenv("WORDPRESS_DB_NAME"), (int) $port); exit(0); }
      catch (Throwable $e) { exit(1); }' 2>/dev/null; then
    break
  fi
  [[ $i -eq 60 ]] && die "Die Datenbank ist nach 2 Minuten nicht erreichbar. Logs: cd $TARGET_DIR && docker compose logs db"
  sleep 2
done

# --- WordPress setup ----------------------------------------------------------

info "Installiere WordPress"
WP_PASSWORD=$(random_string 24)
wpcli core install \
  --url="https://$DOMAIN" \
  --title="$WP_TITLE" \
  --admin_user="$WP_ADMIN" \
  --admin_password="$WP_PASSWORD" \
  --admin_email="$WP_EMAIL" \
  --skip-email
if [[ $WP_LOCALE != en_US ]]; then
  wpcli language core install "$WP_LOCALE" --activate
fi
wpcli option update timezone_string "$WP_TIMEZONE"
wpcli rewrite structure '/%postname%/'
wpcli plugin activate redis-cache
wpcli redis enable

# --- Done ---------------------------------------------------------------------

cat <<EOF

================================================================================
 $DOMAIN ist eingerichtet.

 WordPress-Login:  https://$DOMAIN/wp-admin/
 Benutzer:         $WP_ADMIN
 Passwort:         $WP_PASSWORD     <- jetzt notieren, wird nirgends gespeichert

 Docker-Projekt:   $TARGET_DIR   (Passwörter in .env)
 WordPress:        $HTDOCS_DIR
 Container-Port:   127.0.0.1:$APACHE_PORT
 MariaDB:          127.0.0.1:$MYSQL_PORT   (Benutzer/Passwort in .env)
                   ssh -L 3306:127.0.0.1:$MYSQL_PORT <user>@<server>

 Noch zu tun:
   cp $TARGET_DIR/nginx/$DOMAIN.conf /etc/nginx/sites-available/
   ln -s /etc/nginx/sites-available/$DOMAIN.conf /etc/nginx/sites-enabled/
   nginx -t && systemctl reload nginx
   certbot --nginx $CERTBOT_DOMAINS
================================================================================
EOF
