#!/bin/bash

set -e

# Usage: ./autobot.sh <domain> <email> <nginx_site_file>
if [ "$#" -ne 3 ]; then
  echo "Usage: $0 <domain> <email> <nginx_site_file>"
  exit 1
fi

DOMAIN="$1"
EMAIL="$2"
NGINX_SITE_FILE="$3"

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
sudo certbot certonly --nginx -d "$DOMAIN" --email "$EMAIL" --agree-tos --non-interactive || {
  echo "Certbot failed. Check domain and nginx config.";
  exit 1;
}

CERT_PATH="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
KEY_PATH="/etc/letsencrypt/live/$DOMAIN/privkey.pem"

if [ ! -f "$CERT_PATH" ] || [ ! -f "$KEY_PATH" ]; then
  echo "Certificate files not found."
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
