-- Create the separate primodel_demo database used by the demo seed.
-- This script is executed by postgres:18 docker-entrypoint-initdb.d on first start.
-- The seed command (POST /api/seed-demo-data) connects to this DB to provision
-- physical tables and run integrations; it does NOT create the database itself.
SELECT 'CREATE DATABASE primodel_demo'
  WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'primodel_demo')\gexec
