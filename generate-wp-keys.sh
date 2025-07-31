#!/bin/bash

KEY_NAMES=(
  AUTH_KEY
  SECURE_AUTH_KEY
  LOGGED_IN_KEY
  NONCE_KEY
  AUTH_SALT
  SECURE_AUTH_SALT
  LOGGED_IN_SALT
  NONCE_SALT
)

generate_key() {
  LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 36
}

for KEY in "${KEY_NAMES[@]}"; do
  VALUE=$(generate_key)
  echo "define( '$KEY', '$VALUE' );"
done
