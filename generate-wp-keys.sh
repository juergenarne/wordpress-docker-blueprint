#!/bin/bash

# Platzhalter-Namen in der richtigen Reihenfolge
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

# Funktion zur Generierung eines 36-stelligen zufälligen Strings
generate_key() {
  tr -dc 'A-Za-z0-9' </dev/urandom | head -c 36
}

# Schleife über alle Schlüssel und Ausgabe im define-Format
for KEY in "${KEY_NAMES[@]}"; do
  VALUE=$(generate_key)
  echo "define( '$KEY',  '$VALUE' );"
done
