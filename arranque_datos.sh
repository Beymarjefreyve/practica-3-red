#!/bin/bash
# Script de arranque de la maquina de datos.
set -x
exec > /var/log/arranque-datos.log 2>&1


for intento in 1 2 3 4 5 6 7 8 9 10; do
  apt-get update -y && break
  echo "apt-get update fallo (intento $intento). Sin salida por NAT todavia."
  sleep 10
done

apt-get install -y nginx curl

cat > /etc/nginx/sites-available/default <<'NGINX'
server {
    listen PUERTO_PLACEHOLDER default_server;
    listen [::]:PUERTO_PLACEHOLDER default_server;

    root /var/www/html;

    location / {
        default_type application/json;
        try_files /estado.json =404;
    }
}
NGINX
sed -i "s|PUERTO_PLACEHOLDER|${puerto_datos}|g" /etc/nginx/sites-available/default

INTERNA=$(curl -s -H "Metadata-Flavor: Google" \
  http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/ip)

cat > /var/www/html/estado.json <<JSON
{
  "servicio": "capa-datos",
  "host": "$(hostname)",
  "ip_interna": "$INTERNA",
  "puerto": ${puerto_datos},
  "mensaje": "Dato servido desde la maquina sin IP publica",
  "generado": "$(date -Is)"
}
JSON

rm -f /var/www/html/index.nginx-debian.html
systemctl enable nginx
systemctl restart nginx
