# WordPress blueprint

**Download:**

```bash
git clone https://juergenarne@github.com/juergenarne/wordpress-blueprint.git .
```

**Tweak:**

Modify stuff from the .env file to meet your needs.

To generate WordPress keys execute

```bash
./generate-wp-keys.sh
```

**Run:**

```bash
docker-compose build
docker-compose up -d
````

**Open:** `http://localhost:8085/` and start installing WordPress.
