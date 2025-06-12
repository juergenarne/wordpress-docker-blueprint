# WordPress blueprint

**Download:**

```bash
git clone https://juergenarne@github.com/juergenarne/wordpress-blueprint.git wordpress
```

**Tweak:**
_(optional)_ 

__The package has been set up to work out of the box for development and testing purpouses. If you wish to use the package for production please modifiy database credentials and secrets for secutiry reasons.__ 

Modify stuff from the .env file to meet your needs.
Kepp in mind to update the wp-config.php file if database credentials where modified.

To generate WordPress keys execute

```bash
./generate-wp-keys.sh
```

**Run:**

```bash
docker-compose build
docker-compose up -d
````

**Open:** `http://localhost:8080/` and start installing WordPress.
