-- Create the database
CREATE DATABASE bawas;

-- Create the DBA role
CREATE ROLE dba WITH
    LOGIN
    SUPERUSER
    CREATEDB
    CREATEROLE
    REPLICATION
    BYPASS RLS;

-- Create user hsingh and grant DBA role
CREATE USER hsingh WITH
    LOGIN
    PASSWORD 'your_secure_password_here';

-- Grant DBA role to hsingh
GRANT dba TO hsingh;

-- Connect to the database
\c bawas

-- Grant all privileges on database to dba role
GRANT ALL PRIVILEGES ON DATABASE bawas TO dba;

-- Grant all privileges on all tables to dba role
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO dba;

-- Grant all privileges on all sequences to dba role
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO dba;

-- Set default privileges for future objects
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO dba;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO dba;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO dba; 