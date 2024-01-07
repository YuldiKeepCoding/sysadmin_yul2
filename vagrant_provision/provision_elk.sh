#!/bin/bash

#Actualización
apt-get update >/dev/null 2>&1 && apt-get install -y parted lvm2 >/dev/null 2>&1
#Tabla de particiones MBR
parted -s /dev/sdc mklabel gpt && parted -s -a optimal /dev/sdc mkpart logical 0% 100% && parted -s /dev/sdc 'set 1 lvm on'
#Creación de volumen fisico, volumen group y formateo (ext4)
pvcreate /dev/sdc1 && vgcreate vm2_vg /dev/sdc1 && lvcreate -l 100%FREE vm2_vg -n vm2_data && mkfs.ext4 /dev/vm2_vg/vm2_data
#Creo el direcctorio para montar el volumen
mkdir var/lib/elasticsearch
#Montar volumen en directorio
mount /dev/vm2_vg/vm2_data /var/lib/elasticsearch >/dev/null 2>&1
#Añade texto en la segunda línea de /etc/fstab
echo "/dev/vg_vm2/lv_vm2 /var/lib/elasticsearch ext4 defaults 0 0" | tee -a /etc/fstab
# Aplica los cambios
mount -a

#Borrar direcctorio elasticsearch
rm -rf var/lib/elasticsearch/lost+found

#__Instalación de ElasticSearch__
#Importar la Key de su repositorio.
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | gpg --dearmor -o /usr/share/keyrings/elasticsearch-keyring.gpg #>/dev/null 2>&1
#Instalar comando apt-transport-https
apt-get update && apt-get install -y apt-transport-https
#Añadir el repositorio.
echo "deb [signed-by=/usr/share/keyrings/elasticsearch-keyring.gpg] https://artifacts.elastic.co/packages/8.x/apt stable main" | tee /etc/apt/sources.list.d/elastic-8.x.list
#Actualizar indices APT e instalar ElasticSearch
apt-get update && apt-get install -y elasticsearch
#Asignar permisos al directorio para ElasticSearch
chown -R elasticsearch:elasticsearch /var/lib/elasticsearch
#Habilitar el servicio ElasticSearch
systemctl enable elasticsearch --now
#Regenerar contraseñas de acceso.
ELASTIC_PASSWORD=$(/usr/share/elasticsearch/bin/elasticsearch-reset-password -u elastic -b -s) && echo "PASSWDOD_ELASTIC: $ELASTIC_PASSWORD"
KIBANA_PASSWORD=$(/usr/share/elasticsearch/bin/elasticsearch-reset-password -u kibana_system -b -s) && echo "PASSWDOD_KIBANA: $KIBANA_PASSWORD"

#Instalación Kibana
apt-get update && apt-get install -y kibana
#Crear directorio para certificados de Kibana.
mkdir /etc/kibana/certs
#Copiar el certificado generado por ElasticSearch
cp /etc/elasticsearch/certs/http_ca.crt /etc/kibana/certs/
#Modificar permisos
chown -R kibana:kibana /etc/kibana/certs
#Modificación de parametros para /etc/kibana/kibana.yml
cat <<EOF >/etc/kibana/kibana.yml
server.port: 5601
server.host: 192.168.10.4
elasticsearch.hosts: ["https://localhost:9200"]
elasticsearch.username: "kibana_system"
elasticsearch.password: "${KIBANA_PASSWORD}"
elasticsearch.ssl.certificateAuthorities: ["/etc/kibana/certs/http_ca.crt"]
logging:
  appenders:
    file:
      type: file
      fileName: /var/log/kibana/kibana.log
      layout:
        type: json
  root:
    appenders:
      - default
      - file
pid.file: /run/kibana/kibana.pid
EOF
# Iniciamos y habilitamos kibana
systemctl enable kibana --now


# Actualizar e instalar Logstcash
apt-get update && apt-get install -y logstash
# Crear directorio para el cerificago generado por ElasticSearch
mkdir /etc/logstash/certs
# Copiar el certificado generado por ElasticSearch
cp /etc/elasticsearch/certs/http_ca.crt /etc/logstash/certs/
# Modificar permisos
chown -R logstash:logstash /etc/logstash/certs
# Crear un role y usuario para Logstash
curl -XPOST --cacert /etc/logstash/certs/http_ca.crt -u elastic:$ELASTIC_PASSWORD 'https://localhost:9200/_security/role/logstash_write_role' -H "Content-Type: application/json" -d '
{
    "cluster": [
        "monitor",
        "manage_index_templates"
    ],
    "indices": [
        {
            "names": [
                "*"
            ],
            "privileges": [
                "write",
                "create_index",
                "auto_configure"
            ],
            "field_security": {
                "grant": [
                    "*"
                ]
            }
        }
    ],
    "run_as": [],
    "metadata": {},
    "transient_metadata": {
        "enabled": true
    }
}'
curl -XPOST --cacert /etc/logstash/certs/http_ca.crt -u elastic:$ELASTIC_PASSWORD 'https://localhost:9200/_security/user/logstash' -H "Content-Type: application/json" -d '
{
    "password": "keepcoding_logstash",
    "roles": [
        "logstash_admin",
        "logstash_system",
        "logstash_write_role"
    ],
    "full_name": "Logstash User"
}'

# Crear la configurar los inputs de logstash
cat <<EOF >/etc/logstash/conf.d/02-beats-input.conf
input {
    beats {
        port => 5044
    }
}
EOF

# Crear y configurar los outputs de logstash
cat <<EOF >/etc/logstash/conf.d/30-elasticsearch-output.conf
output {
    elasticsearch {
        hosts => ["https://localhost:9200"]
        manage_template => false
        index => "filebeat-demo-%{+YYYY.MM.dd}"
        user => "logstash"
        password => "keepcoding_logstash"
        cacert => "/etc/logstash/certs/http_ca.crt"
    }
}
EOF
# Inciamos y habilitamos el servicio de logstash
systemctl enable logstash --now

echo "Accederemos a http://localhost:5601 para acceder a Kibana con el usuario: elastic y la contraseña: $ELASTIC_PASSWORD"