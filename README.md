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
