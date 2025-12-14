#!/bin/bash
# this script is a modified version of what Chia-Chin Chung <60947091s@gapps.ntnu.edu.tw> wrote for oqs-demos/mosquitto

########## initialization ##########

# configure the PQC setup 
SIG_ALG="falcon1024"
INSTALLDIR="/opt/oqssa"
export LD_LIBRARY_PATH=/opt/oqssa/lib64
export OPENSSL_CONF=/opt/oqssa/ssl/openssl.cnf
export PATH="/usr/local/bin:/usr/local/sbin:${INSTALLDIR}/bin:$PATH"

# configure the ip addresses
echo "------------------------------------------------------"
read -p "Enter broker IP address: " BROKER_IP
BROKER_IP=${BROKER_IP:-localhost}
read -p "Enter subscriber IP address: " SUB_IP
SUB_IP=${SUB_IP:-localhost}
echo "------------------------------------------------------"

# generate the new subscriber CSR and cert using pre-set CA.key & cert; suppress output
openssl req -new -newkey $SIG_ALG -keyout /pqc-mqtt/cert/subscriber.key -out /pqc-mqtt/cert/subscriber.csr -nodes -subj "/O=pqc-mqtt-subscriber/CN=$SUB_IP" > /dev/null 2>&1
openssl x509 -req -in /pqc-mqtt/cert/subscriber.csr -out /pqc-mqtt/cert/subscriber.crt -CA /pqc-mqtt/cert/CA.crt -CAkey /pqc-mqtt/cert/CA.key -CAcreateserial -days 365 > /dev/null 2>&1

# modify file permissions
chmod 777 /pqc-mqtt/cert/*
 
# execute the mosquitto MQTT subscriber
mosquitto_sub -h $BROKER_IP -t pqc-mqtt-sensor/motion-sensor -q 0 -i "Client_sub" -v \
--tls-version tlsv1.3 --cafile /pqc-mqtt/cert/CA.crt \
--cert /pqc-mqtt/cert/subscriber.crt --key /pqc-mqtt/cert/subscriber.key
