# certbot.sh

A Bash script to automate SSL certificate issuance and renewal for Nginx using Certbot.

## Features
- Installs Certbot if not present
- Requests or renews SSL certificates for a given domain
- Updates Nginx site configuration with certificate paths
- Optionally removes existing certificates and requests a new one (`--force`)
- Reloads Nginx after changes

## Usage

```sh
bash certbot.sh <domain> <email> <nginx_site_file> [--force]
```

- `<domain>`: The domain name to secure (e.g., `example.com`)
- `<email>`: Email address for Let's Encrypt notifications
- `<nginx_site_file>`: Nginx site config file (filename or absolute path)
- `--force` (optional): Remove existing certificate and request a new one

### Examples

Request or renew certificate:
```sh
bash certbot.sh example.com admin@example.com example.com
```

Force remove and request new certificate:
```sh
bash certbot.sh example.com admin@example.com example.com --force
```

## Requirements
- Bash
- Nginx
- Certbot (auto-installed if missing)
- Sudo privileges

## Notes
- The script updates the Nginx config file to use the new certificate paths.
- If the Nginx site file is not an absolute path, `/etc/nginx/sites-available/` is prepended.
- The script reloads Nginx after making changes.
- Use `--force` with caution; it deletes existing certificate files for the domain. 