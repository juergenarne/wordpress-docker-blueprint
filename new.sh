#!/usr/bin/env bash
# Imports a site exported with old.sh into an installation created by init.sh.
#
# Replaces database and wp-content of /opt/wordpress/<domain>. The previous state
# is kept in /opt/wordpress/<domain>/backup/<timestamp>/.
#
# Usage: sudo ./new.sh /root/migration-<domain>-<date>.tar

set -euo pipefail

INSTALL_BASE=/opt/wordpress
HTDOCS_BASE=/var/www/htdocs

die()  { echo "Fehler: $*" >&2; exit 1; }
info() { echo; echo "==> $*"; }

ask() {
  local __var=$1 __prompt=$2 __default=${3:-} __answer
  if [[ -n $__default ]]; then
    read -rp "$__prompt [$__default]: " __answer
  else
    read -rp "$__prompt: " __answer
  fi
  printf -v "$__var" '%s' "${__answer:-$__default}"
}

ask_yes_no() {
  local answer
  read -rp "$1 [$( [[ $2 == y ]] && echo J/n || echo j/N )]: " answer
  answer=${answer:-$2}
  [[ $answer =~ ^[jJyY] ]]
}

set_env() {
  if grep -q "^$1=" "$ENV_FILE"; then
    sed -i "s|^$1=.*|$1=$2|" "$ENV_FILE"
  else
    echo "$1=$2" >> "$ENV_FILE"
  fi
}

wpcli() {
  docker compose exec -T -u www-data -e WP_CLI_CACHE_DIR=/tmp/wp-cli-cache web wp "$@"
}

wait_for_db() {
  local i
  for i in $(seq 1 60); do
    if docker compose exec -T web php -r '
        [$host, $port] = explode(":", getenv("WORDPRESS_DB_HOST")) + [1 => 3306];
        try { new mysqli($host, getenv("WORDPRESS_DB_USER"), getenv("WORDPRESS_DB_PASSWORD"), getenv("WORDPRESS_DB_NAME"), (int) $port); exit(0); }
        catch (Throwable $e) { exit(1); }' 2>/dev/null; then
      return 0
    fi
    sleep 2
  done
  die "Die Datenbank ist nach 2 Minuten nicht erreichbar. Logs: docker compose logs db"
}

# --- Checks -------------------------------------------------------------------

[[ $EUID -eq 0 ]] || die "Bitte als root ausführen: sudo ./new.sh <archiv.tar>"
ARCHIVE=${1:-}
[[ -n $ARCHIVE ]] || die "Aufruf: sudo ./new.sh /root/migration-<domain>-<datum>.tar"
[[ -f $ARCHIVE ]] || die "Archiv nicht gefunden: $ARCHIVE"
ARCHIVE=$(cd "$(dirname "$ARCHIVE")" && pwd)/$(basename "$ARCHIVE")

umask 077
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

info "Entpacke $ARCHIVE"
tar -C "$WORK_DIR" -xf "$ARCHIVE"
for f in migration.env db.sql.gz wp-content.tgz; do
  [[ -f $WORK_DIR/$f ]] || die "$f fehlt im Archiv. Wurde es mit old.sh erstellt?"
done

OLD_PREFIX=$(grep '^TABLE_PREFIX=' "$WORK_DIR/migration.env" | cut -d= -f2-)
OLD_HOME=$(grep '^HOME_URL=' "$WORK_DIR/migration.env" | cut -d= -f2-)
OLD_SITEURL=$(grep '^SITE_URL=' "$WORK_DIR/migration.env" | cut -d= -f2-)
[[ $OLD_PREFIX =~ ^[A-Za-z0-9_]+$ ]] || die "Ungültiges Tabellen-Präfix im Archiv: '$OLD_PREFIX'"

DEFAULT_DOMAIN=$(sed -E 's|^https?://||; s|/.*$||; s|^www\.||' <<< "$OLD_HOME")
ask DOMAIN "Domain auf diesem Server" "$DEFAULT_DOMAIN"

TARGET_DIR=$INSTALL_BASE/$DOMAIN
HTDOCS_DIR=$HTDOCS_BASE/$DOMAIN
ENV_FILE=$TARGET_DIR/.env
NEW_URL=$(grep '^WORDPRESS_URL=' "$ENV_FILE" 2>/dev/null | cut -d= -f2- || true)

[[ -f $ENV_FILE ]]   || die "$ENV_FILE fehlt. Bitte zuerst init.sh für $DOMAIN ausführen."
[[ -d $HTDOCS_DIR ]] || die "$HTDOCS_DIR fehlt. Bitte zuerst init.sh für $DOMAIN ausführen."

echo
echo "Alte Seite:    $OLD_HOME (Präfix $OLD_PREFIX)"
echo "Neue Seite:    $NEW_URL"
echo "Docker:        $TARGET_DIR"
echo "WordPress:     $HTDOCS_DIR"
echo
echo "Datenbank und wp-content von $DOMAIN werden ERSETZT."
ask_yes_no "Fortfahren?" n || die "Abgebrochen."

cd "$TARGET_DIR"
docker compose up -d
wait_for_db

# --- Backup of the current state ----------------------------------------------

BACKUP_DIR=$TARGET_DIR/backup/$(date +%Y%m%d-%H%M%S)
info "Sichere aktuellen Stand nach $BACKUP_DIR"
mkdir -p "$BACKUP_DIR/old-server"
chmod 700 "$TARGET_DIR/backup"
docker compose exec -T db sh -c 'mariadb-dump -uroot -p"$MYSQL_ROOT_PASSWORD" --single-transaction "$MYSQL_DATABASE"' \
  | gzip > "$BACKUP_DIR/db-before-import.sql.gz"
mv "$HTDOCS_DIR/wp-content" "$BACKUP_DIR/wp-content"
for f in wp-config.php .htaccess info.txt migration.env; do
  [[ -f $WORK_DIR/$f ]] && cp "$WORK_DIR/$f" "$BACKUP_DIR/old-server/"
done

# --- Database -----------------------------------------------------------------

info "Importiere Datenbank"
set_env WORDPRESS_TABLE_PREFIX "$OLD_PREFIX"
docker compose exec -T db sh -c 'mariadb -uroot -p"$MYSQL_ROOT_PASSWORD" -e "
  DROP DATABASE IF EXISTS \`$MYSQL_DATABASE\`;
  CREATE DATABASE \`$MYSQL_DATABASE\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"'
# MySQL 8 collations are unknown to MariaDB
gunzip -c "$WORK_DIR/db.sql.gz" \
  | sed -e 's/utf8mb4_0900_ai_ci/utf8mb4_unicode_ci/g' \
  | docker compose exec -T db sh -c 'mariadb -uroot -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE"'

# --- wp-content ---------------------------------------------------------------

info "Übernehme wp-content"
tar -C "$HTDOCS_DIR" -xzf "$WORK_DIR/wp-content.tgz"
rm -f "$HTDOCS_DIR/wp-content/object-cache.php" "$HTDOCS_DIR/wp-content/advanced-cache.php"
if [[ ! -d $HTDOCS_DIR/wp-content/plugins/redis-cache ]]; then
  cp -a "$BACKUP_DIR/wp-content/plugins/redis-cache" "$HTDOCS_DIR/wp-content/plugins/"
fi
chown -R www-data:www-data "$HTDOCS_DIR"
find "$HTDOCS_DIR" -type d -exec chmod 755 {} +
find "$HTDOCS_DIR" -type f -exec chmod 644 {} +

# --- WordPress ----------------------------------------------------------------

info "Passe WordPress an"
docker compose up -d   # picks up the new table prefix
wait_for_db
wpcli core update-db
if [[ -n $NEW_URL && $OLD_HOME != "$NEW_URL" ]]; then
  wpcli search-replace "$OLD_HOME" "$NEW_URL" --all-tables-with-prefix --skip-columns=guid --report-changed-only
fi
if [[ $OLD_SITEURL != "$OLD_HOME" ]]; then
  echo "    Hinweis: siteurl ($OLD_SITEURL) weicht von home ($OLD_HOME) ab."
  echo "    Der Blueprint setzt beide auf $NEW_URL, Pfade in Inhalten ggf. prüfen."
fi
wpcli plugin activate redis-cache
wpcli redis enable || echo "    Redis-Objekt-Cache konnte nicht aktiviert werden, bitte im Backend prüfen."
wpcli rewrite flush
wpcli cache flush

ACTIVE_PLUGINS=$(wpcli plugin list --status=active --field=name | tr '\n' ' ')

cat <<EOF

================================================================================
 Import für $DOMAIN abgeschlossen.

 Es gelten jetzt die Logins der alten Seite.
 Aktive Plugins: $ACTIVE_PLUGINS

 Bitte prüfen:
   - Eigene Konstanten und Regeln der alten Seite: $BACKUP_DIR/old-server/
     (info.txt, wp-config.php, .htaccess) – bei Bedarf in wp-config.php übernehmen
   - Caching- und Sicherheits-Plugins mit Serverpfaden neu einrichten
   - Vor der DNS-Umstellung per /etc/hosts auf dem eigenen Rechner testen

 Vorheriger Stand: $BACKUP_DIR
 Archiv löschen, wenn alles passt: rm $ARCHIVE
================================================================================
EOF
