# WordPress blueprint

WordPress 7.1 on PHP 8.5 (Apache), MariaDB and Redis with Docker Compose.

## Server installation (Ubuntu)

**Requirements:** Docker with the Compose plugin (`docker compose`), nginx, certbot, rsync.

```bash
sudo git clone https://github.com/juergenarne/wordpress-docker-blueprint.git /opt/wordpress/blueprint
cd /opt/wordpress/blueprint
sudo ./init.sh
```

`init.sh` asks for the domain, the WordPress admin and (optionally) SMTP access, then:

- copies the Docker project to `/opt/wordpress/<domain>` (owned by root) and creates its `.env`
  with random database passwords, WordPress keys and salts, table prefix and free local ports
- copies WordPress to `/var/www/htdocs/<domain>` (owned by www-data)
- creates `msmtprc` for outgoing mail
- builds and starts the containers and installs WordPress via WP-CLI
  (language, timezone, permalinks, Redis object cache)
- writes the nginx relay config to `/opt/wordpress/<domain>/nginx/<domain>.conf`

The admin password is shown once at the end. Then enable the site and get a certificate:

```bash
cp /opt/wordpress/<domain>/nginx/<domain>.conf /etc/nginx/sites-available/
ln -s /etc/nginx/sites-available/<domain>.conf /etc/nginx/sites-enabled/
nginx -t && systemctl reload nginx
certbot --nginx -d <domain>
```

Run `init.sh` again from the blueprint for every further domain.

Apache and MariaDB are bound to `127.0.0.1` only; Redis is not published at all. To reach the
database from outside, open an SSH tunnel (`MYSQL_PORT` from `/opt/wordpress/<domain>/.env`):

```bash
ssh -L 3306:127.0.0.1:<MYSQL_PORT> user@server
```

Then connect your database client to `127.0.0.1:3306`.

## Migrating an existing site

On the **old server** (classic installation with PHP CLI and database access), copy `old.sh`
there and run it:

```bash
sudo ./old.sh /path/to/wordpress
```

It optionally enables maintenance mode, writes an inventory (versions, plugins, custom
constants) and creates `~/migration-<domain>-<date>.tar` with the database dump and
`wp-content` (without caches and backup folders). Copy the archive to the new server.

On the **new server**, after `init.sh` for the same domain:

```bash
sudo /opt/wordpress/blueprint/new.sh /root/migration-<domain>-<date>.tar
```

It backs up the fresh installation to `/opt/wordpress/<domain>/backup/<timestamp>/`, imports
the database with the old table prefix, replaces `wp-content`, updates the database schema,
rewrites URLs if they changed (e.g. `http://` to `https://`) and enables the Redis cache. The
logins of the old site apply afterwards.

Test the new server via `/etc/hosts` on your own machine before switching DNS.

## Local development

```bash
cp .env.dist .env
cp msmtprc.dist msmtprc
./generate-wp-keys.sh   # paste the output into .env
docker compose build
docker compose up -d
```

**Open:** `http://localhost:8080/` and start installing WordPress.

Database credentials, keys and salts are read from `.env`; `wp-config.php` contains no secrets.
