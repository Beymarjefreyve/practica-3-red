#!/bin/bash
# Script de arranque de la maquina de aplicacion.
# La pagina no es estatica: consulta la capa de datos en cada peticion, asi que
# si la maquina privada no responde, la pagina no se puede servir (503).
set -x
exec > /var/log/arranque-app.log 2>&1

apt-get update -y
apt-get install -y nginx php-fpm curl

# La version de php-fpm depende de la imagen (Debian 12 -> 8.2). En vez de
# fijarla, buscamos el socket que haya quedado.
for intento in 1 2 3 4 5 6 7 8 9 10; do
  PHP_SOCK=$(ls /run/php/php*-fpm.sock 2>/dev/null | head -n1)
  [ -n "$PHP_SOCK" ] && break
  sleep 3
done

cat > /etc/nginx/sites-available/default <<'NGINX'
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    root /var/www/html;
    index index.php;

    location / {
        try_files $uri $uri/ /index.php;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:PHP_SOCK_PLACEHOLDER;
    }
}
NGINX
sed -i "s|PHP_SOCK_PLACEHOLDER|$PHP_SOCK|" /etc/nginx/sites-available/default

INTERNA=$(curl -s -H "Metadata-Flavor: Google" \
  http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/ip)
echo "$INTERNA" > /var/www/html/ip-interna.txt

rm -f /var/www/html/index.nginx-debian.html

cat > /var/www/html/index.php <<'PHP'
<?php
$backend = "http://${ip_datos}:${puerto_datos}/";
$contexto = stream_context_create(["http" => ["timeout" => 5, "ignore_errors" => true]]);
$crudo = @file_get_contents($backend, false, $contexto);

$codigo = 0;
if (isset($http_response_header[0]) && preg_match("/\s(\d{3})\s/", $http_response_header[0], $m)) {
    $codigo = (int) $m[1];
}

// Sin capa de datos no hay pagina. Esta es la dependencia real.
if ($crudo === false || $codigo !== 200) {
    http_response_code(503);
    header("Content-Type: text/html; charset=utf-8");
    echo "<!DOCTYPE html><html lang='es'><head><meta charset='utf-8'>";
    echo "<title>503 - capa de datos no disponible</title></head><body>";
    echo "<h1>503 - Servicio no disponible</h1>";
    echo "<p>La capa de datos (${ip_datos}:${puerto_datos}) no responde.</p>";
    echo "<p>Esta pagina no se puede servir sin ella.</p>";
    echo "</body></html>";
    exit;
}

$datos = json_decode($crudo, true);
$interna_app = trim(@file_get_contents("/var/www/html/ip-interna.txt"));
header("Content-Type: text/html; charset=utf-8");
?>
<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="utf-8">
  <title>${identificacion}</title>
  <style>
    body { font-family: system-ui, Arial, sans-serif; margin: 2rem auto; max-width: 46rem; line-height: 1.5; }
    .caja { border: 1px solid #ccc; border-radius: 6px; padding: 1rem 1.25rem; }
    .dato { background: #f3f6f9; border-left: 4px solid #1a73e8; padding: .75rem; font-family: monospace; white-space: pre-wrap; }
    table { border-collapse: collapse; margin-top: 1rem; }
    td { padding: .2rem .8rem .2rem 0; }
  </style>
</head>
<body>
  <h1>${identificacion}</h1>
  <p>Servidor de aplicacion. Capa publica de la practica 3.</p>

  <table>
    <tr><td>IP interna de esta maquina</td><td><code><?= htmlspecialchars($interna_app) ?></code></td></tr>
    <tr><td>Capa de datos consultada</td><td><code>${ip_datos}:${puerto_datos}</code></td></tr>
  </table>

  <h2>Dato recibido de la maquina privada</h2>
  <div class="caja">
    <p>Servido por <strong><?= htmlspecialchars($datos["host"] ?? "?") ?></strong>,
       IP interna <strong><?= htmlspecialchars($datos["ip_interna"] ?? "?") ?></strong>,
       sin direccion publica.</p>
    <div class="dato"><?= htmlspecialchars($crudo) ?></div>
  </div>

  <p><small>Consultado en <?= date("c") ?>. Si la maquina privada se apaga, esta pagina devuelve 503.</small></p>
</body>
</html>
PHP

systemctl enable nginx
systemctl restart php*-fpm 2>/dev/null || systemctl restart php-fpm
systemctl restart nginx
