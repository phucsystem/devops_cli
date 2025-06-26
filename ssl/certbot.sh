#!/bin/bash

set -e

# Usage: ./autobot.sh <domain> <email> <nginx_site_file> [--force]
if [ "$#" -lt 3 ] || [ "$#" -gt 4 ]; then
  echo "Usage: $0 <domain> <email> <nginx_site_file> [--force]"
  exit 1
fi

DOMAIN="$1"
EMAIL="$2"
NGINX_SITE_FILE="$3"
FORCE_RENEWAL=false
if [ "$4" == "--force" ]; then
  FORCE_RENEWAL=true
fi

# If the nginx site file is not an absolute path, prepend /etc/nginx/sites-available/
if [[ "$NGINX_SITE_FILE" != /* ]]; then
  NGINX_SITE_FILE="/etc/nginx/sites-available/$NGINX_SITE_FILE"
fi

# Check if certbot is installed
if ! command -v certbot >/dev/null 2>&1; then
  echo "certbot not found. Installing..."
  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update && sudo apt-get install -y certbot python3-certbot-nginx
  elif command -v yum >/dev/null 2>&1; then
    sudo yum install -y certbot python3-certbot-nginx
  elif command -v brew >/dev/null 2>&1; then
    brew install certbot
  else
    echo "Package manager not found. Please install certbot manually."
    exit 1
  fi
fi

# Obtain/renew certificate only (do not auto-edit nginx)
CERTBOT_OUTPUT=$(mktemp)
sudo certbot certonly --nginx -d "$DOMAIN" --email "$EMAIL" --agree-tos --non-interactive > "$CERTBOT_OUTPUT" 2>&1 || {
  cat "$CERTBOT_OUTPUT"
  echo "Certbot failed. Check domain and nginx config.";
  rm -f "$CERTBOT_OUTPUT"
  exit 1;
}

if grep -q "Certificate not yet due for renewal" "$CERTBOT_OUTPUT"; then
  echo "Certificate not yet due for renewal; no action taken. Exiting."
  rm -f "$CERTBOT_OUTPUT"
  exit 0
fi

rm -f "$CERTBOT_OUTPUT"

CERT_PATH="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
KEY_PATH="/etc/letsencrypt/live/$DOMAIN/privkey.pem"

if [ "$FORCE_RENEWAL" = true ]; then
  echo "Force removal of existing certificate for $DOMAIN..."
  sudo rm -rf "/etc/letsencrypt/live/$DOMAIN" "/etc/letsencrypt/archive/$DOMAIN" "/etc/letsencrypt/renewal/$DOMAIN.conf"
fi

if [ ! -f "$CERT_PATH" ] || [ ! -f "$KEY_PATH" ]; then
  echo "Certificate files not found: $CERT_PATH or $KEY_PATH. Exiting."
  exit 1
fi

# Update nginx site file with SSL cert paths
if grep -q "ssl_certificate " "$NGINX_SITE_FILE"; then
  sudo sed -i.bak "/ssl_certificate /c\\    ssl_certificate $CERT_PATH;" "$NGINX_SITE_FILE"
else
  sudo sed -i.bak "/server_name.*$DOMAIN.*/a\\    ssl_certificate $CERT_PATH;" "$NGINX_SITE_FILE"
fi

if grep -q "ssl_certificate_key " "$NGINX_SITE_FILE"; then
  sudo sed -i.bak "/ssl_certificate_key /c\\    ssl_certificate_key $KEY_PATH;" "$NGINX_SITE_FILE"
else
  sudo sed -i.bak "/ssl_certificate $CERT_PATH;/a\\    ssl_certificate_key $KEY_PATH;" "$NGINX_SITE_FILE"
fi

# Ensure listen 443 ssl is present
if ! grep -q "listen 443 ssl" "$NGINX_SITE_FILE"; then
  sudo sed -i.bak "/server_name.*$DOMAIN.*/a\\    listen 443 ssl;" "$NGINX_SITE_FILE"
fi

echo "Reloading nginx..."
sudo nginx -s reload || sudo systemctl reload nginx || {
  echo "Failed to reload nginx. Please check nginx status.";
  exit 1;
}

echo "SSL setup complete for $DOMAIN and updated $NGINX_SITE_FILE."
