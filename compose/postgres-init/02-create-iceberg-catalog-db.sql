-- Create the separate iceberg_catalog database used by the Iceberg REST catalog (lake overlay, opt-in).
-- This script is executed by postgres:18 docker-entrypoint-initdb.d on first start.
-- Only runs on a FRESH data directory — an existing install that enables the lake overlay later gets
-- this database from the postgres-catalog-init one-shot service in docker-compose.lake.yml instead.
SELECT 'CREATE DATABASE iceberg_catalog'
  WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'iceberg_catalog')\gexec
