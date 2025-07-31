# DNS Credentials Configuration

This directory contains DNS provider credentials for Let's Encrypt DNS-01 challenge authentication. The DNS-01 challenge is required for wildcard SSL certificates.

## Supported DNS Providers

The following DNS providers are supported:

- **Cloudflare** (`dns-cloudflare`)
- **AWS Route53** (`dns-route53`)
- **DigitalOcean** (`dns-digitalocean`)
- **Google Cloud DNS** (`dns-google`)
- **OVH** (`dns-ovh`)

## Quick Setup

Use the setup script to configure your DNS provider:

```bash
# Configure Cloudflare
./scripts/setup-dns-provider.sh cloudflare

# Configure AWS Route53
./scripts/setup-dns-provider.sh route53
```

## Manual Configuration

### 1. Choose Your DNS Provider

Copy the appropriate example file and configure it:

```bash
# For Cloudflare
cp cloudflare.ini.example cloudflare.ini

# For AWS Route53
cp route53.ini.example route53.ini
```

### 2. Configure Credentials

Edit the credentials file with your API credentials:

```bash
# Set proper permissions (important for security)
chmod 600 cloudflare.ini

# Edit the file
nano cloudflare.ini
```

### 3. Update Environment Variables

Update your `.env` file:

```bash
# Set the DNS plugin
DNS_PLUGIN=dns-cloudflare

# Update the Certbot image
CERTBOT_IMAGE=certbot/dns-cloudflare:latest
```

Or use the helper script:

```bash
./scripts/update-certbot-image.sh
```

## Provider-Specific Setup

### Cloudflare

1. **Get API Token** (Recommended):
   - Go to [Cloudflare API Tokens](https://dash.cloudflare.com/profile/api-tokens)
   - Create a token with permissions:
     - Zone:Zone:Read
     - Zone:DNS:Edit
   - Include your domain in the zone resources

2. **Configure credentials**:
   ```ini
   dns_cloudflare_api_token = your-api-token-here
   ```

3. **Alternative: Global API Key** (Less secure):
   ```ini
   dns_cloudflare_email = your-email@cloudflare.com
   dns_cloudflare_api_key = your-global-api-key
   ```

### AWS Route53

1. **Create IAM User**:
   - Create an IAM user with programmatic access
   - Attach policy with permissions:
     - `route53:GetChange`
     - `route53:ChangeResourceRecordSets`
     - `route53:ListHostedZonesByName`

2. **Configure credentials**:
   ```ini
   dns_route53_access_key_id = your-access-key-id
   dns_route53_secret_access_key = your-secret-access-key
   ```

### DigitalOcean

1. **Get API Token**:
   - Go to [DigitalOcean API](https://cloud.digitalocean.com/account/api/tokens)
   - Generate a new token with read/write scope

2. **Configure credentials**:
   ```ini
   dns_digitalocean_token = your-api-token
   ```

### Google Cloud DNS

1. **Create Service Account**:
   - Create a service account in Google Cloud Console
   - Grant DNS Administrator role
   - Download the JSON key file

2. **Configure credentials**:
   ```ini
   dns_google_credentials = /path/to/service-account-key.json
   ```

### OVH

1. **Get API Credentials**:
   - Go to [OVH API](https://eu.api.ovh.com/createToken/)
   - Request credentials with DNS rights

2. **Configure credentials**:
   ```ini
   dns_ovh_endpoint = ovh-eu
   dns_ovh_application_key = your-application-key
   dns_ovh_application_secret = your-application-secret
   dns_ovh_consumer_key = your-consumer-key
   ```

## Security Best Practices

1. **File Permissions**: Always set credentials files to 600:
   ```bash
   chmod 600 dns-credentials/*.ini
   ```

2. **Least Privilege**: Use API tokens with minimal required permissions

3. **Regular Rotation**: Rotate API credentials regularly

4. **Backup**: Keep secure backups of your credentials

5. **Environment Variables**: Never commit credentials to version control

## Troubleshooting

### Common Issues

1. **Permission Denied**:
   ```bash
   chmod 600 dns-credentials/your-provider.ini
   ```

2. **Invalid Credentials**:
   - Verify API token/key is correct
   - Check token permissions and scope
   - Ensure domain is included in token scope

3. **DNS Propagation**:
   - DNS changes can take time to propagate
   - Certbot will wait for propagation automatically

4. **Rate Limits**:
   - Let's Encrypt has rate limits
   - Use staging environment for testing

### Testing Your Setup

Test your DNS credentials before running the full setup:

```bash
# Test Cloudflare credentials
docker run --rm -it \
  -v $(pwd)/dns-credentials:/etc/letsencrypt/dns-credentials:ro \
  certbot/dns-cloudflare:latest \
  certbot certonly --dns-cloudflare \
  --dns-cloudflare-credentials /etc/letsencrypt/dns-credentials/cloudflare.ini \
  --email your-email@example.com \
  --agree-tos --no-eff-email \
  --staging \
  -d test.yourdomain.com
```

### Log Files

Check the following log files for troubleshooting:

- `/var/log/letsencrypt/certbot.log` - Certbot operations
- `/var/log/letsencrypt/combine-certs.log` - Certificate combination
- Docker container logs: `docker logs certbot-ssl`

## File Structure

```
dns-credentials/
├── README.md                    # This file
├── .gitkeep                     # Keep directory in git
├── cloudflare.ini.example       # Cloudflare template
├── route53.ini.example          # AWS Route53 template
├── digitalocean.ini.example     # DigitalOcean template
├── google.ini.example           # Google Cloud DNS template
├── ovh.ini.example              # OVH template
├── cloudflare.ini               # Your Cloudflare credentials (gitignored)
├── route53.ini                  # Your Route53 credentials (gitignored)
└── ...                          # Other provider credentials (gitignored)
```

## Support

For provider-specific issues:

- **Cloudflare**: [Cloudflare API Documentation](https://api.cloudflare.com/)
- **AWS Route53**: [Route53 API Documentation](https://docs.aws.amazon.com/route53/)
- **DigitalOcean**: [DigitalOcean API Documentation](https://docs.digitalocean.com/reference/api/)
- **Google Cloud**: [Cloud DNS API Documentation](https://cloud.google.com/dns/docs)
- **OVH**: [OVH API Documentation](https://docs.ovh.com/gb/en/)

For Certbot issues: [Certbot Documentation](https://certbot.eff.org/docs/)