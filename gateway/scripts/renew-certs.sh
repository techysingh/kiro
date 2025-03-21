#!/bin/bash

# Renew certificates
docker-compose run --rm certbot renew

# Convert certificates to HAProxy format
for domain in $(ls /etc/letsencrypt/live/); do
    cat "/etc/letsencrypt/live/$domain/fullchain.pem" "/etc/letsencrypt/live/$domain/privkey.pem" > "/etc/haproxy/certs/$domain.pem"
done

# Reload HAProxy configuration
docker-compose exec haproxy haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg
docker-compose kill -s HUP haproxy 