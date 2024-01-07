#!/bin/bash

# \\ Diseñado por Yul \\

echo "Comienza la instalación" 
#Actualización
apt-get update && apt-get install -y parted lvm2
#Tabla de particiones MBR
parted -s /dev/sdc mklabel gpt && parted -s -a optimal /dev/sdc mkpart logical 0% 100% && parted -s /dev/sdc 'set 1 lvm on'
#Creación de volumen fisico, volumen group y formateo (ext4)
pvcreate /dev/sdc1 && vgcreate vm1_vg /dev/sdc1 && lvcreate -l 100%FREE vm1_vg -n vm1_data && mkfs.ext4 /dev/vm1_vg/vm1_data
#Creo el direcctorio para montar el volumen
mkdir /var/lib/mysql
#Montar volumen en directorio
mount /dev/vm1_vg/vm1_data /var/lib/mysql
#Añade texto en la segunda línea de /etc/fstab
echo "/dev/vg_vm1/lv_vm1 /var/lib/mysql ext4 defaults 0 0" | tee -a /etc/fstab
# Aplica los cambios
mount -a

#Borrar direcctorio /lost+found/
rm -r /var/lib/mysql/lost+found


echo "Dame un segundo :)"
#Actualizar repositorios e instalar paquetes necesarios
apt-get update 
apt install -y nginx mariadb-server mariadb-common php-fpm php-mysql expect php-curl php-gd php-intl php-mbstring php-soap php-xml php-xmlrpc php-zip


echo "Ves, no era para tanto!!"
rm /etc/nginx/sites-enabled/default
rm /etc/nginx/sites-available/default
# Managed by installation script - Do not change
cat <<EOF >/etc/nginx/sites-available/wordpress
server {
    listen 80;
    root /var/www/wordpress;
    index index.php index.html index.htm index.nginx-debian.html;
    server_name localhost;

    location / {
        try_files \$uri \$uri/ =404;
    }
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.1-fpm.sock;
    }
    location ~ /\.ht {
        deny all;
    }
}
EOF

#Enlace simbólico
ln -s "/etc/nginx/sites-available/wordpress" "/etc/nginx/sites-enabled/"
#Reiniciar el servicio
systemctl restart nginx
# Reiniciamos php-fpm
systemctl restart php8.1-fpm

#Securizando la BBDD de MySQL
yes | mysql_secure_installation
openssl rand -hex 15 > MARIADB_PASSWORD.txt && RANDOM_PASSWORD=$(cat MARIADB_PASSWORD.txt)
mysql --user=root --password=$RANDOM_PASSWORD -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${RANDOM_PASSWORD}'; DELETE FROM mysql.user WHERE User=''; DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1'); DROP DATABASE IF EXISTS test; DELETE FROM mysql.db WHERE Db='test' OR Db='test\_%'; FLUSH PRIVILEGES;"

#Descargar Last Release de WordPress
wget https://wordpress.org/latest.tar.gz
# Creamos directorio para la instalación de Wordpress
mkdir /var/www/wordpress
# Descomprimimos el fichero en el directorio creado
tar -xzvf latest.tar.gz -C /var/www/
#Creación BBDD WordPress
mysql --user=root --password=$RANDOM_PASSWORD -e "CREATE DATABASE wordpress DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci; GRANT ALL ON wordpress.* TO 'wordpressuser'@'localhost' IDENTIFIED BY 'keepcoding'; FLUSH PRIVILEGES;"

cp /var/www/wordpress/wp-config-sample.php /var/www/wordpress/wp-config.php
#Modificar configuración en wp.config.php
sed '23,29 d' </var/www/wordpress/wp-config-sample.php >/var/www/wordpress/wp-config.php && sed '23 a define( "DB_NAME", "wordpress" );' -i /var/www/wordpress/wp-config.php && sed '24 a /** Database username */' -i /var/www/wordpress/wp-config.php && sed '25 a define( "DB_USER", "wordpressuser" );' -i /var/www/wordpress/wp-config.php && sed '26 a /** Database password */' -i /var/www/wordpress/wp-config.php && sed '27 a define( "DB_PASSWORD", "keepcoding" );' -i /var/www/wordpress/wp-config.php
# Asignar permisos de usuario y grupo: www-data
chown -R www-data:www-data /var/www/wordpress


echo "Entrando en la ultima fase..."

#__Instalación de Filebeat__
#Importar la Key de su repositorio.
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | apt-key add -
#Añadir el repositorio.
echo "deb https://artifacts.elastic.co/packages/8.x/apt stable main" | tee -a /etc/apt/sources.list.d/elastic-8.x.list
#Actualizar indices APT e instalar filebeat
apt-get update && sudo apt-get install -y filebeat

#Habilitar el modulo de system y nginx
filebeat modules enable system
filebeat modules enable nginx
# Configurar Filebeat
touch /etc/filebeat/filebeat.yml
cat <<EOF >/etc/filebeat/filebeat.yml
# ============================== Filebeat inputs ===============================

filebeat.inputs:
- type: log
  enabled: true
  paths:
    - /var/log/*.log
    - /var/log/nginx/*.log
    - /var/log/mysql/*.log

# ------------------------------ Logstash Output -------------------------------
output.logstash:
  # The Logstash hosts
  hosts: ["192.168.10.4:5044"]
EOF
# Habilitar y arrancar servicio de Filebeat
systemctl enable filebeat --now 
#Confirmación al usuario
echo -e "READY!! \n  - La configuración ha termiando :) \n  - Accede a: http://localhost:8081/ para comenzar la instalación"