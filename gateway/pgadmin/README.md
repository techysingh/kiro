# pgAdmin Setup

This directory contains the configuration for running pgAdmin in a Docker container with externalized storage and configuration.

## Directory Structure

```
pgadmin/
├── docker-compose.yml    # Docker compose configuration
├── .env                 # Environment variables (credentials)
├── servers.json         # Pre-configured database connections
├── data/               # Persistent data storage
└── config/             # Configuration files
```

## Configuration Files

### docker-compose.yml
- Container name: pgadmin
- Image: dpage/pgadmin4:latest
- Port: 5050 (non-privileged)
- Volumes:
  - ./data:/var/lib/pgadmin
  - ./config:/etc/pgadmin
  - ./servers.json:/pgadmin4/servers.json

### .env
Contains sensitive configuration:
- PGADMIN_DEFAULT_EMAIL: admin@bawas.com
- PGADMIN_DEFAULT_PASSWORD: (secure password)

### servers.json
Pre-configured database connection:
- Name: Bawas Database
- Host: 192.168.0.178
- Port: 5432
- Database: bawas
- Username: hsingh
- SSL Mode: prefer

## Security Features

1. Strong password stored in separate .env file
2. Non-privileged port (5050)
3. Persistent storage for configuration
4. Pre-configured server connections
5. SSL mode enabled for database connections

## Usage

1. Navigate to the pgAdmin directory:
```bash
cd gateway/pgadmin
```

2. Start the container:
```bash
docker compose up -d
```

3. Access pgAdmin web interface:
```
http://192.168.0.178:5050
```

## Login Credentials

- Email: admin@bawas.com
- Password: (from .env file)

## Database Connection

The servers.json file contains a pre-configured connection to the Bawas database:
- Host: 192.168.0.178
- Port: 5432
- Database: bawas
- Username: hsingh
- SSL Mode: prefer

## Maintenance

### Backup
The configuration and data are stored in the following directories:
- ./data: Contains pgAdmin data
- ./config: Contains pgAdmin configuration
- ./servers.json: Contains pre-configured server connections

### Updates
To update pgAdmin:
```bash
docker compose pull
docker compose up -d
```

## Security Notes

1. Keep the .env file secure and never commit it to version control
2. Regularly update the password in the .env file
3. Monitor the logs for any suspicious activity
4. Keep the Docker image updated for security patches

## Troubleshooting

1. If the container fails to start, check the logs:
```bash
docker compose logs pgadmin
```

2. If you can't connect to the web interface:
   - Verify the container is running: `docker compose ps`
   - Check if port 5050 is accessible
   - Verify the credentials in .env file

3. If database connection fails:
   - Verify the database server is running
   - Check the credentials in servers.json
   - Verify network connectivity to the database server 