#!/bin/bash
set -e

echo "Running migrations on public schema..."
python manage.py migrate_schemas --shared || echo "Public schema migration failed, continuing..."

echo "Running migrations on tenant schemas (if any)..."
python manage.py migrate_schemas --tenant || echo "Tenant migrations failed, continuing..."

echo "Starting Gunicorn..."
exec gunicorn axis_saas.wsgi:application --bind 0.0.0.0:7860 --workers 3 --threads 2
