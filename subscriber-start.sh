#!/bin/bash
# this script is a modified version of what Chia-Chin Chung <60947091s@gapps.ntnu.edu.tw> wrote for oqs-demos/mosquitto

########## functions ##########

# to pretty print the time in nanoseconds
now_ns() {
    date +%s%N
}

# to log the cert gen time to ./results.csv
log_result() {
    echo "$PQC_ALG,$1,$2" >> "$RESULTS_FILE"
}

########## initialization ##########

# set the alg and log vars
PQC_ALG=${PQC_ALG:-falcon1024}
RESULTS_FILE=${RESULTS_FILE:-results.csv}

# define the signature algorithm(s) in use
if [ "$PQC_ALG" = "rsa" ]; then
    SIG_ALG="rsa:2048"
else
    SIG_ALG="falcon1024"
fi

# define the install paths
INSTALLDIR="/opt/oqssa"
export LD_LIBRARY_PATH=/opt/oqssa/lib64
export OPENSSL_CONF=/opt/oqssa/ssl/openssl.cnf
export PATH="/usr/local/bin:/usr/local/sbin:${INSTALLDIR}/bin:$PATH"

# load the ip addresses
source ./pqc-env.sh
echo "------------------------------------------------------"
BROKER_IP=${BROKER_IP:-localhost}
echo "Using broker IP:     $BROKER_IP"
SUB_IP=${SUB_IP:-localhost}
echo "Using subscriber IP: $SUB_IP"
echo "------------------------------------------------------"

# time the cert generation
CERT_START=$(now_ns)
openssl req -new -newkey $SIG_ALG \
  -keyout /pqc-mqtt/cert/subscriber.key \
  -out /pqc-mqtt/cert/subscriber.csr \
  -nodes -subj "/O=pqc-mqtt-subscriber/CN=$SUB_IP" > /dev/null 2>&1

openssl x509 -req -in /pqc-mqtt/cert/subscriber.csr \
  -out /pqc-mqtt/cert/subscriber.crt \
  -CA /pqc-mqtt/cert/CA.crt \
  -CAkey /pqc-mqtt/cert/CA.key \
  -CAcreateserial -days 365 > /dev/null 2>&1

CERT_END=$(now_ns)
CERT_NS=$((CERT_END - CERT_START))

# log the results
log_result "subscriber_cert" "$CERT_NS"

# give mosquitto permissions to the working directory
chmod 777 /pqc-mqtt/cert/*

# start the subscriber
mosquitto_sub -h $BROKER_IP -t pqc-mqtt-sensor/motion-sensor -q 0 -i "Client_sub" -v \
--tls-version tlsv1.3 --cafile /pqc-mqtt/cert/CA.crt \
--cert /pqc-mqtt/cert/subscriber.crt --key /pqc-mqtt/cert/subscriber.key