#!/bin/bash
set -e

echo "🚀 Iniciando instalación del entorno MyEMS..."

# 1. Dependencias base
echo "📦 Instalando dependencias..."
sudo apt update
sudo apt install -y git python3 python3-venv python3-pip mysql-server nginx curl nodejs npm

# 2. Clonar repositorio
echo "📂 Clonando repositorio..."
if [ ! -d "myems" ]; then
    git clone https://github.com/MyEMS/myems.git
fi
cd myems/

# 3. Configurar MySQL
echo "🗄️ Configurando base de datos MySQL..."
sudo mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '!MyEMS1'; FLUSH PRIVILEGES;"

cd database/install/
for file in *.sql; do
    echo "Cargando $file..."
    mysql -u root -p!MyEMS1 < "$file"
done

cd ../demo-en/
mysql -u root -p!MyEMS1 < myems_system_db.sql
cd ../../

# 4. Servicios Python
start_service() {
    local service=$1
    echo "⚙️ Configurando servicio: $service"
    cd $service
    python3 -m venv venv
    source venv/bin/activate
    pip install --upgrade pip
    pip install -r requirements.txt
    cp example.env .env
    chmod +x run.sh
    echo "✅ Servicio $service configurado. Recuerda ejecutar './run.sh' en una terminal separada."
    deactivate
    cd ..
}

for srv in myems-api myems-modbus-tcp myems-cleaning myems-normalization myems-aggregation; do
    start_service $srv
done

# 5. MyEMS Admin
echo "🌐 Configurando MyEMS Admin..."
sudo mkdir -p /var/www
sudo cp -r ~/myems/myems-admin /var/www/myems-admin
sudo chmod -R 755 /var/www/myems-admin
sudo tee /etc/nginx/conf.d/myems-admin.conf > /dev/null <<'EOF'
server {
    listen 8081;
    server_name localhost;
    root /var/www/myems-admin;
    index index.html;
    location / {
        try_files $uri $uri/ /index.html;
    }
    location /api {
        proxy_pass http://127.0.0.1:8000/;
        proxy_connect_timeout 75;
        proxy_read_timeout 600;
        send_timeout 600;
    }
}
EOF

# 6. MyEMS Web
echo "🌍 Configurando MyEMS Web..."
cd ~/myems/myems-web
npm install --unsafe-perm=true --allow-root --legacy-peer-deps
npm run build
sudo rm -rf /var/www/myems-web
sudo cp -r ~/myems/myems-web /var/www/myems-web
sudo chmod -R 755 /var/www/myems-web
sudo tee /etc/nginx/conf.d/myems-web.conf > /dev/null <<'EOF'
server {
    listen 80;
    server_name myems-web;
    location / {
        root /var/www/myems-web;
        index index.html index.htm;
        try_files $uri /index.html;
    }
    location /api {
        proxy_pass http://127.0.0.1:8000/;
        proxy_connect_timeout 75;
        proxy_read_timeout 600;
        send_timeout 600;
    }
}
EOF

sudo nginx -t
sudo systemctl restart nginx
sudo ufw allow 80
sudo ufw allow 8081

echo "✅ Instalación completa."
echo "Admin: http://$(hostname -I | awk '{print $1}'):8081"
echo "Web:   http://$(hostname -I | awk '{print $1}')/"
