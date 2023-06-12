#!/bin/bash

function EPHEMERAL_PORT() {
    LOW_BOUND=49152
    RANGE=16384
    while true; do
        CANDIDATE=$[$LOW_BOUND + ($RANDOM % $RANGE)]
        (echo "" >/dev/tcp/127.0.0.1/${CANDIDATE}) >/dev/null 2>&1
        if [ $? -ne 0 ]; then
            echo $CANDIDATE
            break
        fi
    done
}

if [ $# -eq 0 ]; then
	echo "No arguments supplied"
	exit 0
fi

input=$1
mkdir tmp
currentDirectory=$(pwd)
MYSQL_ROOT_USER=root
MYSQL_ROOT_PASSWORD=root
MYSQL_REPLICATION_USER=user
MYSQL_REPLICATION_PASSWORD=user

for i in $(seq 1 $((input+3)));
do
	echo "PORT$i=$(EPHEMERAL_PORT)" >> $currentDirectory/.env
done

cat << EOF > $currentDirectory/docker-compose.yml
version: "3.8"
services:
  mysql_master:
    image: mysql:latest
    container_name: mysql_master
    hostname: mysql_master
    expose:
      - "3306"
    ports:
      - "\${PORT1}:3306"
    environment:
      MYSQL_ROOT_USER: $MYSQL_ROOT_USER
      MYSQL_ROOT_PASSWORD: $MYSQL_ROOT_PASSWORD
      MYSQL_REPLICATION_USER: $MYSQL_REPLICATION_USER
      MYSQL_REPLICATION_PASSWORD: $MYSQL_REPLICATION_PASSWORD
    volumes:
      - data_master:/var/lib/mysql
      - ./tmp/master-my.cnf:/etc/my.cnf
    networks:
      mysql_net:
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "mysql --user=$MYSQL_ROOT_USER --password=$MYSQL_ROOT_PASSWORD --host=localhost --execute='SELECT 1;'"]
      timeout: 10s
      retries: 10
      interval: 5s
    deploy:
      resources:
        limits:
          cpus: "0.5"
          memory: 512M
  init:
    image: mysql:latest
    container_name: init
    hostname: init
    depends_on:
          mysql_master:
                 condition: service_healthy
EOF

for w in $(seq 1 $input);
do
cat << EOF >> $currentDirectory/docker-compose.yml
          mysql_slave_$w:
                 condition: service_healthy
EOF
done

cat << EOF >> $currentDirectory/docker-compose.yml
    expose:
      - "3306"
    ports:
      - "\${PORT2}:3306"
    environment:
      MYSQL_ROOT_USER: $MYSQL_ROOT_USER
      MYSQL_ROOT_PASSWORD: $MYSQL_ROOT_PASSWORD
      MYSQL_REPLICATION_USER: $MYSQL_REPLICATION_USER
      MYSQL_REPLICATION_PASSWORD: $MYSQL_REPLICATION_PASSWORD
    volumes:
      - ./tmp/init.sh:/init.sh
    command: /bin/bash -x init.sh
    networks:
      mysql_net:
    restart: "no"
    deploy:
      resources:
        limits:
          cpus: "0.5"
          memory: 512M
  populate:
    image: mysql:latest
    container_name: populate
    hostname: populate
    depends_on:
      init:
        condition: service_completed_successfully
    expose:
      - "3306"
    ports:
      - "\${PORT3}:3306"
    environment:
      MYSQL_ROOT_USER: $MYSQL_ROOT_USER
      MYSQL_ROOT_PASSWORD: $MYSQL_ROOT_PASSWORD
      MYSQL_REPLICATION_USER: $MYSQL_REPLICATION_USER
      MYSQL_REPLICATION_PASSWORD: $MYSQL_REPLICATION_PASSWORD
    volumes:
      - ./tmp/populate.sh:/populate.sh
    networks:
      mysql_net:
    restart: "no"
    deploy:
      resources:
        limits:
          cpus: "0.5"
          memory: 512M
    command: /bin/bash +x populate.sh
EOF

for q in $(seq 1 $input);
do
cat << EOF >> $currentDirectory/docker-compose.yml
  mysql_slave_$q:
    image: mysql:latest
    container_name: mysql_slave_$q
    hostname: mysql_slave_$q
    expose:
      - "3306"
    ports:
      - "\${PORT$((q+3))}:3306"
    environment:
      MYSQL_ROOT_USER: $MYSQL_ROOT_USER
      MYSQL_ROOT_PASSWORD: $MYSQL_ROOT_PASSWORD
      MYSQL_REPLICATION_USER: $MYSQL_REPLICATION_USER
      MYSQL_REPLICATION_PASSWORD: $MYSQL_REPLICATION_PASSWORD
    volumes:
      - data_slave_$q:/var/lib/mysql
      - ./tmp/slave_$q-my.cnf:/etc/my.cnf
    networks:
      mysql_net:
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "mysql --user=$MYSQL_ROOT_PASSWORD --password=$MYSQL_ROOT_PASSWORD --host=localhost --execute='SELECT 1;'"]
      timeout: 10s
      retries: 10
      interval: 5s
    deploy:
      resources:
        limits:
          cpus: "0.5"
          memory: 512M
EOF
done

cat << EOF >> $currentDirectory/docker-compose.yml
volumes:
  data_master:
EOF

for r in $(seq 1 $input);
do
cat << EOF >> $currentDirectory/docker-compose.yml
  data_slave_$r:
EOF
done

cat << EOF >> $currentDirectory/docker-compose.yml
networks:
  mysql_net:
    ipam:
      driver: default
      config:
        - subnet: "10.0.0.0/24"
EOF

cat << EOF > $currentDirectory/tmp/master-my.cnf
[mysqld]
server-id = 1
log-bin = mysql-bin
log-slave-updates = 1
datadir = /var/lib/mysql
bind-address = 0.0.0.0
skip-host-cache
skip-name-resolve
EOF

for k in $(seq 1 $input);
do
cat << EOF > $currentDirectory/tmp/slave_$k-my.cnf
[mysqld]
server-id = $((k+1))
log-bin = mysql-bin
log-slave-updates = 1
read-only = 1
skip-host-cache
skip-name-resolve
EOF
done

cat << EOF > $currentDirectory/tmp/init.sh
#!/bin/bash
mysql -hmysql_master -u\$MYSQL_ROOT_USER -p\$MYSQL_ROOT_PASSWORD -e "CREATE USER '\$MYSQL_REPLICATION_USER'@'%' IDENTIFIED BY '\$MYSQL_REPLICATION_PASSWORD';"
mysql -hmysql_master -u\$MYSQL_ROOT_USER -p\$MYSQL_ROOT_PASSWORD -e "GRANT REPLICATION SLAVE ON *.* TO '\$MYSQL_REPLICATION_USER'@'%';"
mysql -hmysql_master -u\$MYSQL_ROOT_USER -p\$MYSQL_ROOT_PASSWORD -e "FLUSH PRIVILEGES;"
mysql -hmysql_master -u\$MYSQL_ROOT_USER -p\$MYSQL_ROOT_PASSWORD -e "ALTER USER '\$MYSQL_REPLICATION_USER'@'%' IDENTIFIED WITH mysql_native_password BY '\$MYSQL_REPLICATION_PASSWORD';"
mysql -hmysql_master -u\$MYSQL_ROOT_USER -p\$MYSQL_ROOT_PASSWORD -e "FLUSH PRIVILEGES;"
master_position=\$(mysql -hmysql_master -u\$MYSQL_ROOT_USER -p\$MYSQL_ROOT_PASSWORD -e "SHOW MASTER STATUS\G" | grep "Position:" | awk '{print \$2}')
master_log_file=\$(mysql -hmysql_master -u\$MYSQL_ROOT_USER -p\$MYSQL_ROOT_PASSWORD -e "SHOW MASTER STATUS\G" | grep "File:" | awk '{print \$2}')
EOF

for h in $(seq 1 $input);
do
cat << EOF >> $currentDirectory/tmp/init.sh
mysql -hmysql_slave_$h -u\$MYSQL_ROOT_USER -p\$MYSQL_ROOT_PASSWORD -e "STOP SLAVE;"
mysql -hmysql_slave_$h -u\$MYSQL_ROOT_USER -p\$MYSQL_ROOT_PASSWORD -e "RESET SLAVE ALL;"
mysql -hmysql_slave_$h -u\$MYSQL_ROOT_USER -p\$MYSQL_ROOT_PASSWORD -e "CHANGE MASTER TO MASTER_HOST='mysql_master', MASTER_USER='\$MYSQL_REPLICATION_USER', MASTER_PASSWORD='\$MYSQL_REPLICATION_PASSWORD', MASTER_LOG_FILE='\${master_log_file}', MASTER_LOG_POS=\${master_position};"
mysql -hmysql_slave_$h -u\$MYSQL_ROOT_USER -p\$MYSQL_ROOT_PASSWORD -e "START SLAVE;"
mysql -hmysql_slave_$h -u\$MYSQL_ROOT_USER -p\$MYSQL_ROOT_PASSWORD -e "SHOW SLAVE STATUS\G;"
EOF
done

cat << EOF > $currentDirectory/tmp/populate.sh
#!/bin/bash
mysql -hmysql_master -u\$MYSQL_ROOT_USER -p\$MYSQL_ROOT_PASSWORD -e "
CREATE DATABASE IF NOT EXISTS testDB;
USE testDB;
CREATE TABLE IF NOT EXISTS testTABLE(
    id INT AUTO_INCREMENT,
    data VARCHAR(100),
    PRIMARY KEY(id)
);

DELIMITER //
CREATE PROCEDURE insertData()
BEGIN
    DECLARE i INT DEFAULT 0;
    WHILE i < 200 DO
        INSERT INTO testTABLE (data) VALUES (CONCAT('Data', i));
        SET i = i + 1;
    END WHILE;
END;
//

CALL insertData();
DROP PROCEDURE IF EXISTS insertData;
"
EOF

docker-compose up -d
