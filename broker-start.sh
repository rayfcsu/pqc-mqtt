#!/bin/bash
# this script is a modified version of what Chia-Chin Chung <60947091s@gapps.ntnu.edu.tw> wrote for oqs-demos/mosquitto

########## functions ##########

copy_ca_certificate() {
    local user=$1
    local host=$2
    local remote_path=$3
    local role=$4
    
    if [ -n "$user" ]; then
        echo "$user@$host CA key/cert configuration"
        echo "------------------------------------------------------"

        # copy files to /tmp first (can't scp directly to / )
        if scp /pqc-mqtt/CA.crt /pqc-mqtt/CA.key "$user@$host:/tmp/"; then
            echo "Success   :   files copied to /tmp/ on $user@$host."
        else
            echo "Failure   :   cannot copy CA files to remote host."
            return 1
        fi

        # move CA cert and key to /pqc-mqtt/cert
        if ssh "$user@$host" "
            sudo mkdir -p '$remote_path' && \
            sudo cp /tmp/CA.crt /tmp/CA.key '$remote_path'/ && \
            sudo chmod 777 '$remote_path'/CA.crt && \
            sudo chmod 777 '$remote_path'/CA.key && \
            sudo rm -f /tmp/CA.crt /tmp/CA.key
        "; then
            echo "Success   : installed CA certificate and key to $user@$host:$remote_path/."
        else
            echo "Failure   : cannot move files to final $remote_path/."
            return 1
        fi
    fi
}

########## instrumentation ##########

# set the alg and log vars
PQC_ALG=${PQC_ALG:-falcon1024}
RESULTS_FILE=${RESULTS_FILE:-results.csv}

now_ns() {
    date +%s%N
}

log_result() {
    echo "$PQC_ALG,$1,$2" >> "$RESULTS_FILE"
}

########## initialization ##########

# configure the PQC setup
if [ "$PQC_ALG" = "rsa" ]; then
    SIG_ALG="rsa:2048"
else
    SIG_ALG="falcon1024"
fi

INSTALLDIR="/opt/oqssa"
export LD_LIBRARY_PATH=/opt/oqssa/lib64
export OPENSSL_CONF=/opt/oqssa/ssl/openssl.cnf
export PATH="/usr/local/bin:/usr/local/sbin:${INSTALLDIR}/bin:$PATH"

########## IP configuration ##########

echo "------------------------------------------------------"
read -p "Enter broker IP address: " BROKER_IP
BROKER_IP=${BROKER_IP:-localhost}
read -p "Enter publisher IP address: " PUB_IP
PUB_IP=${PUB_IP:-localhost}
read -p "Enter subscriber IP address: " SUB_IP
SUB_IP=${SUB_IP:-localhost}
echo "------------------------------------------------------"

# get SCP configuration
echo "The CA certificate will be copied to subscriber and publisher hosts."
read -p "Enter SSH username for PUBLISHER ($PUB_IP): " PUB_USER
read -p "Enter SSH username for SUBSCRIBER ($SUB_IP): " SUB_USER
echo "------------------------------------------------------"

########## main ##########

# generate the CA key and PQC certificates; suppress output
cd /pqc-mqtt

CERT_START=$(now_ns)
openssl req -x509 -new -newkey $SIG_ALG \
    -keyout /pqc-mqtt/CA.key \
    -out /pqc-mqtt/CA.crt \
    -nodes -subj "/O=pqc-mqtt-ca" -days 3650 > /dev/null 2>&1
CERT_END=$(now_ns)
CERT_TIME_MS=$(( (CERT_END - CERT_START) / 1000000 ))
log_result "ca_generation" "$CERT_TIME_MS"

# copy CA cert to publisher and subscriber
if [ "$PUB_IP" != "localhost" ] && [ -n "$PUB_USER" ]; then
    copy_ca_certificate "$PUB_USER" "$PUB_IP" "/pqc-mqtt/cert" "publisher"
    echo "------------------------------------------------------"
fi

if [ "$SUB_IP" != "localhost" ] && [ -n "$SUB_USER" ]; then
    copy_ca_certificate "$SUB_USER" "$SUB_IP" "/pqc-mqtt/cert" "subscriber"
    echo "------------------------------------------------------"
fi

# generate the configuration file for mosquitto
echo -e "
## Listeners
listener 8883
max_connections -1
max_qos 2
protocol mqtt

## General configuration
allow_anonymous false

## Certificate based SSL/TLS support
cafile /pqc-mqtt/cert/CA.crt
keyfile /pqc-mqtt/cert/broker.key
certfile /pqc-mqtt/cert/broker.crt
tls_version tlsv1.3
ciphers_tls1.3 TLS_AES_128_GCM_SHA256

# Comment out the following two lines if using one-way authentication
require_certificate true

## Same as above
use_identity_as_username true
" > mosquitto.conf

# generate the password file(add username and password) for the mosquitto MQTT broker
mosquitto_passwd -b -c passwd broker 12345

# generate the Access Control List
echo -e "user broker\ntopic readwrite pqc-mqtt-sensor/motion-sensor" > acl

# create the cert directory
mkdir -p /pqc-mqtt/cert

# copy the CA key and the cert to the cert folder
cp /pqc-mqtt/CA.key /pqc-mqtt/CA.crt /pqc-mqtt/cert

# time the cert generation
BROKER_CERT_START=$(now_ns)
openssl req -new -newkey $SIG_ALG \
    -keyout /pqc-mqtt/cert/broker.key \
    -out /pqc-mqtt/cert/broker.csr \
    -nodes -subj "/O=pqc-mqtt-broker/CN=$BROKER_IP" > /dev/null 2>&1

openssl x509 -req -in /pqc-mqtt/cert/broker.csr \
    -out /pqc-mqtt/cert/broker.crt \
    -CA /pqc-mqtt/cert/CA.crt \
    -CAkey /pqc-mqtt/cert/CA.key \
    -CAcreateserial -days 365 > /dev/null 2>&1

BROKER_CERT_END=$(now_ns)
BROKER_CERT_MS=$(( (BROKER_CERT_END - BROKER_CERT_START) / 1000000 ))
log_result "broker_cert" "$BROKER_CERT_MS"

chmod 777 /pqc-mqtt/cert/*

# time the starting of the broker
BROKER_START=$(now_ns)
mosquitto -c mosquitto.conf -v &
BROKER_PID=$!

for i in {1..30}; do
    if nc -z localhost 8883 2>/dev/null; then
        break
    fi
    sleep 0.1
done

BROKER_READY=$(now_ns)
BROKER_START_MS=$(( (BROKER_READY - BROKER_START) / 1000000 ))
log_result "broker_startup" "$BROKER_START_MS"

wait $BROKER_PID
