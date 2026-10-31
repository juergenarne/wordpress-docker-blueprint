#!/usr/bin/env bash
# Exports an existing WordPress site on the OLD server for migration to this blueprint.
#
# Creates ~/migration-<domain>-<date>.tar containing:
#   db.sql.gz        database dump
#   wp-content.tgz   themes, plugins, uploads, languages (without caches and backups)
#   wp-config.php    old config, for reference only
#   .htaccess        old rules, for reference only
#   info.txt         inventory (versions, plugins, custom constants)
#   migration.env    values new.sh needs (table prefix, URLs)
#
# Usage: sudo ./old.sh [/path/to/wordpress]

set -euo pipefail

die()  { echo "Fehler: $*" >&2; exit 1; }
info() { echo; echo "==> $*"; }

ask_yes_no() {
  local answer
  read -rp "$1 [$( [[ $2 == y ]] && echo J/n || echo j/N )]: " answer
  answer=${answer:-$2}
  [[ $answer =~ ^[jJyY] ]]
}

# --- Checks -------------------------------------------------------------------

WP_DIR=${1:-}
if [[ -z $WP_DIR ]]; then
  [[ -f wp-config.php ]] && WP_DIR=$PWD || read -rp "Pfad zur WordPress-Installation: " WP_DIR
fi
WP_DIR=$(cd "$WP_DIR" && pwd)
[[ -f $WP_DIR/wp-config.php ]] || die "Keine wp-config.php in $WP_DIR gefunden."
[[ -d $WP_DIR/wp-content ]]    || die "Kein wp-content in $WP_DIR gefunden."
command -v php >/dev/null      || die "PHP (CLI) ist nicht installiert."

OWNER=$(stat -c %U "$WP_DIR/wp-config.php")
TOOLS_DIR=$(mktemp -d)
umask 077
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR" "$TOOLS_DIR"' EXIT

if command -v wp >/dev/null; then
  WP_BIN=(wp)
else
  info "Lade WP-CLI (temporär)"
  curl -fsSL -o "$TOOLS_DIR/wp-cli.phar" https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
  chmod 755 "$TOOLS_DIR" && chmod 644 "$TOOLS_DIR/wp-cli.phar"
  WP_BIN=(php "$TOOLS_DIR/wp-cli.phar")
fi

# Run WP-CLI as the owner of the installation
wpcli() {
  if [[ $EUID -eq 0 && $OWNER != root ]]; then
    runuser -u "$OWNER" -- "${WP_BIN[@]}" --path="$WP_DIR" "$@"
  else
    "${WP_BIN[@]}" --path="$WP_DIR" --allow-root "$@"
  fi
}

wpcli db check >/dev/null 2>&1 || die "WP-CLI erreicht die Datenbank nicht. Läuft die Seite in Docker? Dann old.sh im Container ausführen."

HOME_URL=$(wpcli option get home)
SITE_URL=$(wpcli option get siteurl)
PREFIX=$(wpcli db prefix)
WP_VERSION=$(wpcli core version)
DOMAIN=$(sed -E 's|^https?://||; s|/.*$||; s|^www\.||' <<< "$HOME_URL")
OUT_FILE=$HOME/migration-$DOMAIN-$(date +%Y%m%d-%H%M).tar
[[ $OUT_FILE == "$WP_DIR"/* ]] && die "$HOME liegt in der WordPress-Installation, der Export wäre öffentlich erreichbar."

echo
echo "WordPress:   $WP_DIR (Besitzer: $OWNER)"
echo "URL:         $HOME_URL"
echo "Version:     $WP_VERSION, Tabellen-Präfix: $PREFIX"
echo "wp-content:  $(du -sh "$WP_DIR/wp-content" | cut -f1)"
echo "Ziel:        $OUT_FILE"
echo

# --- Freeze -------------------------------------------------------------------

if ask_yes_no "Wartungsmodus aktivieren? (empfohlen, damit nach dem Export keine Änderungen verloren gehen)" y; then
  wpcli maintenance-mode activate
  echo "    Zurücknehmen mit: cd $WP_DIR && wp maintenance-mode deactivate"
fi

# --- Inventory ----------------------------------------------------------------

info "Bestandsaufnahme"
cat > "$WORK_DIR/migration.env" <<EOF
TABLE_PREFIX=$PREFIX
HOME_URL=$HOME_URL
SITE_URL=$SITE_URL
WP_VERSION=$WP_VERSION
EXPORTED=$(date -Iseconds)
EOF

{
  echo "Export von $HOME_URL am $(date)"
  echo "Pfad: $WP_DIR"
  echo
  echo "WordPress: $WP_VERSION"
  echo "PHP:       $(php -r 'echo PHP_VERSION;')"
  echo "Präfix:    $PREFIX"
  echo "home:      $HOME_URL"
  echo "siteurl:   $SITE_URL"
  echo
  echo "--- Plugins"
  wpcli plugin list --fields=name,status,version,update
  echo
  echo "--- Themes"
  wpcli theme list --fields=name,status,version,update
  echo
  echo "--- Eigene Konstanten in wp-config.php (ohne Passwörter und Keys)"
  grep -E "^\s*define\s*\(" "$WP_DIR/wp-config.php" | grep -vE "DB_(NAME|USER|PASSWORD|HOST|CHARSET|COLLATE)|_KEY|_SALT|ABSPATH" || true
  echo
  echo "--- Drop-ins in wp-content"
  ls "$WP_DIR/wp-content"/*.php 2>/dev/null | xargs -n1 basename | grep -v '^index.php$' || true
} > "$WORK_DIR/info.txt" 2>&1
cat "$WORK_DIR/info.txt"

# --- Export -------------------------------------------------------------------

info "Exportiere Datenbank"
wpcli db export - --single-transaction | gzip > "$WORK_DIR/db.sql.gz"
gzip -t "$WORK_DIR/db.sql.gz"

info "Packe wp-content"
tar -C "$WP_DIR" -czf "$WORK_DIR/wp-content.tgz" \
  --exclude=wp-content/cache \
  --exclude=wp-content/upgrade \
  --exclude=wp-content/upgrade-temp-backup \
  --exclude=wp-content/object-cache.php \
  --exclude=wp-content/advanced-cache.php \
  --exclude=wp-content/updraft \
  --exclude=wp-content/ai1wm-backups \
  --exclude=wp-content/backups-dup-lite \
  --exclude=wp-content/backups-dup-pro \
  --exclude=wp-content/debug.log \
  wp-content

cp "$WP_DIR/wp-config.php" "$WORK_DIR/wp-config.php"
[[ -f $WP_DIR/.htaccess ]] && cp "$WP_DIR/.htaccess" "$WORK_DIR/.htaccess"

tar -C "$WORK_DIR" -cf "$OUT_FILE" .
chmod 600 "$OUT_FILE"

cat <<EOF

================================================================================
 Export fertig: $OUT_FILE ($(du -h "$OUT_FILE" | cut -f1))

 Die Datei enthält die komplette Datenbank, bitte vertraulich behandeln.

 Weiter auf dem neuen Server:
   scp $OUT_FILE <user>@<neuer-server>:/root/
   sudo /opt/wordpress/blueprint/init.sh            # falls noch nicht geschehen
   sudo /opt/wordpress/blueprint/new.sh /root/$(basename "$OUT_FILE")
================================================================================
EOF
