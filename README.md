# Secure Home Network Setup

This repository contains a Docker Compose setup for running Pi-hole (ad blocking), HAProxy (reverse proxy), and OpenVPN (VPN server) with Google Authenticator 2FA integration.

## Prerequisites

- Docker and Docker Compose installed
- Domain name with DNS configured for *.irvh.bawas.com
- Port 80, 443 (HAProxy), 53 (Pi-hole), and 1194 (OpenVPN) forwarded to the host

## Directory Structure

```
.
├── config/
│   ├── haproxy/
│   ├── openvpn/
│   └── pihole/
├── data/
│   ├── haproxy/
│   ├── openvpn/
│   └── pihole/
├── scripts/
│   ├── setup-openvpn.sh
│   └── renew-certs.sh
├── docker-compose.yml
└── README.md
```

## Initial Setup

1. Clone this repository
2. Create a `.env` file with the following content:
   ```
   PIHOLE_PASSWORD=your_secure_password
   ```

3. Initialize the services:
   ```bash
   # Create required directories
   mkdir -p config/{pihole,haproxy,openvpn} scripts data/{pihole,haproxy,openvpn}
   
   # Start the services
   docker-compose up -d
   
   # Setup OpenVPN with Google Authenticator
   chmod +x scripts/setup-openvpn.sh
   ./scripts/setup-openvpn.sh
   
   # Setup SSL certificate auto-renewal
   chmod +x scripts/renew-certs.sh
   ```

4. Add the following to your crontab to auto-renew SSL certificates:
   ```bash
   0 0 * * * /path/to/scripts/renew-certs.sh
   ```

## Features

### Pi-hole
- Blocks ads and trackers network-wide
- Blocks social media platforms (Facebook, YouTube, Instagram, etc.)
- Web interface available at https://pihole.irvh.bawas.com

### HAProxy
- SSL termination with Let's Encrypt certificates
- Automatic certificate renewal
- Reverse proxy for Pi-hole and OpenVPN Admin
- Handles all subdomains of *.irvh.bawas.com

### OpenVPN
- Secure remote access to home network
- Google Authenticator 2FA integration
- Individual configurations for users: psingh, hsingh, ishpreet

## User Setup

### VPN Configuration
1. Each user's OpenVPN configuration is available in `config/openvpn/<username>.ovpn`
2. Google Authenticator secrets are in `config/openvpn/<username>.google_authenticator`
3. Users should:
   - Import their .ovpn file into their OpenVPN client
   - Scan the QR code or use the secret from their .google_authenticator file
   - Use their username and current Google Authenticator code when connecting

## Maintenance

### SSL Certificates
- Certificates auto-renew via the cron job
- Manual renewal possible with `./scripts/renew-certs.sh`

### Pi-hole
- Access the admin interface at https://pihole.irvh.bawas.com
- Default password is set in the .env file

### Logs
- View logs with `docker-compose logs [service]`
- Services: pihole, haproxy, openvpn, certbot

## Security Notes

1. Keep the .env file secure and backed up
2. Regularly update containers with `docker-compose pull && docker-compose up -d`
3. Monitor logs for suspicious activity
4. Keep Google Authenticator secrets secure
5. Regularly backup the data directory
