# Custom Certbot image with GoDaddy DNS support
FROM certbot/certbot:latest

# Install GoDaddy DNS plugin
RUN pip install certbot-dns-godaddy

# Set working directory
WORKDIR /opt/certbot

# Copy any custom scripts if needed
# COPY scripts/ /opt/certbot/scripts/

# Default command
CMD ["certbot"]