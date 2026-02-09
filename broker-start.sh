#!/bin/bash
# this script is a modified version of what Chia-Chin Chung <60947091s@gapps.ntnu.edu.tw> wrote for oqs-demos/mosquitto

########## functions ##########

# to scp CA cert and CA key to publisher and subscriber from the broker
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

# to pretty print the time in nanoseconds
now_ns() {
    date +%s%N
}

# to log the cert gen time to ./results.csv
log_result() {
    echo "$PQC_ALG,$1,$2" >> "$RESULTS_FILE"
}

# trap ctrl + c for cleanup efforts
cleanup() {
    echo ""
    echo "Stopping broker (PID: $BROKER_PID)..."
    kill $BROKER_PID 2>/dev/null
    wait $BROKER_PID 2>/dev/null
    echo "Broker stopped."
    echo "Final results in: $RESULTS_FILE"
    exit 0
}

########## initialization ##########

# set the alg and log vars
PQC_ALG=${PQC_ALG:-falcon1024}
RESULTS_FILE=${RESULTS_FILE:-results.csv}

# create the results file
touch "$RESULTS_FILE"

# define the signature algorithm(s) in use
if [ "$PQC_ALG" = "rsa" ]; then
    SIG_ALG="rsa:2048"
else
    SIG_ALG="falcon1024"
fi

# define the install and library paths
INSTALLDIR="/opt/oqssa"
export LD_LIBRARY_PATH=/opt/oqssa/lib64
export OPENSSL_CONF=/opt/oqssa/ssl/openssl.cnf
export PATH="/usr/local/bin:/usr/local/sbin:${INSTALLDIR}/bin:$PATH"

# load the ip addresses
source ./pqc-env.sh
echo "------------------------------------------------------"
BROKER_IP=${BROKER_IP:-localhost}
echo "Using broker IP:     $BROKER_IP"
PUB_IP=${PUB_IP:-localhost}
echo "Using publisher IP: $PUB_IP"
SUB_IP=${SUB_IP:-localhost}
echo "Using subscriber IP: $SUB_IP"
echo "------------------------------------------------------"

# get SCP configuration
echo "The CA certificate will be copied to subscriber and publisher hosts."
read -p "Enter SSH username for PUBLISHER ($PUB_IP): " PUB_USER
read -p "Enter SSH username for SUBSCRIBER ($SUB_IP): " SUB_USER
echo "------------------------------------------------------"

########## main ##########

# enter the working directory
cd /pqc-mqtt

# create the cert directory
mkdir -p /pqc-mqtt/cert

# generate & time the CA key and PQC certificates; suppress output
CERT_START=$(now_ns)
openssl req -x509 -new -newkey $SIG_ALG \
    -keyout /pqc-mqtt/cert/CA.key \
    -out /pqc-mqtt/cert/CA.crt \
    -nodes -subj "/O=pqc-mqtt-ca" -days 3650 > /dev/null 2>&1

CERT_END=$(now_ns)
CERT_TIME_NS=$((CERT_END - CERT_START))

# log the results
log_result "ca_generation" "$CERT_TIME_NS"

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

## general config
allow_anonymous false

## cert based ssl/tls support
cafile /pqc-mqtt/cert/CA.crt
keyfile /pqc-mqtt/cert/broker.key
certfile /pqc-mqtt/cert/broker.crt
tls_version tlsv1.3
ciphers_tls1.3 TLS_AES_128_GCM_SHA256

## authentication 
require_certificate true
use_identity_as_username true
" > mosquitto.conf

# generate the password file(add username and password) for the mosquitto MQTT broker
mosquitto_passwd -b -c passwd broker 12345

# generate the access control list
echo -e "user broker\ntopic readwrite pqc-mqtt-sensor/motion-sensor" > acl

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
BROKER_CERT_NS=$((BROKER_CERT_END - BROKER_CERT_START))

# log the results
log_result "broker_cert" "$BROKER_CERT_NS"

# give mosquitto permissions to the working directory
chmod 777 /pqc-mqtt/cert/*

# execute the mosquitto MQTT broker
mosquitto -c mosquitto.conf -v