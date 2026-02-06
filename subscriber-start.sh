#!/bin/bash
# this script is a modified version of what Chia-Chin Chung <60947091s@gapps.ntnu.edu.tw> wrote for oqs-demos/mosquitto

########## instrumentation ##########

PQC_ALG=${PQC_ALG:-falcon1024}
RESULTS_FILE=${RESULTS_FILE:-results.csv}

now_ns() { date +%s%N; }
log_result() { echo "$PQC_ALG,$1,$2" >> "$RESULTS_FILE"; }

########## initialization ##########

if [ "$PQC_ALG" = "rsa" ]; then
    SIG_ALG="rsa:2048"
else
    SIG_ALG="falcon1024"
fi

INSTALLDIR="/opt/oqssa"
export LD_LIBRARY_PATH=/opt/oqssa/lib64
export OPENSSL_CONF=/opt/oqssa/ssl/openssl.cnf
export PATH="/usr/local/bin:/usr/local/sbin:${INSTALLDIR}/bin:$PATH"

echo "------------------------------------------------------"
read -p "Enter broker IP address: " BROKER_IP
BROKER_IP=${BROKER_IP:-localhost}
read -p "Enter subscriber IP address: " SUB_IP
SUB_IP=${SUB_IP:-localhost}
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
CERT_NS=$(( (CERT_END - CERT_START) / 1000000000 ))
log_result "subscriber_cert" "$CERT_NS"

chmod 777 /pqc-mqtt/cert/*

########## testing ##########
mosquitto_sub -h $BROKER_IP -t pqc-mqtt-sensor/motion-sensor -q 0 -i "Client_sub" \
--tls-version tlsv1.3 --cafile /pqc-mqtt/cert/CA.crt \
--cert /pqc-mqtt/cert/subscriber.crt --key /pqc-mqtt/cert/subscriber.key | \

while read -r LINE; do

    TIMESTAMP_STR=$(echo "$LINE" | grep -o '\[[^]]*\]' | tr -d '[]')
    if [ -n "$TIMESTAMP_STR" ]; then
        
        DATE_PART=$(echo "$TIMESTAMP_STR" | cut -d: -f1-3)  
        NANO_PART=$(echo "$TIMESTAMP_STR" | cut -d: -f4) 

        if command -v date &> /dev/null; then
            SEND_SECONDS=$(date -d "$DATE_PART" +%s 2>/dev/null)
            
            if [ -z "$SEND_SECONDS" ]; then
                SEND_SECONDS=$(date -j -f "%Y-%m-%d %H:%M:%S" "$DATE_PART" +%s 2>/dev/null)
            fi
            
            if [ -n "$SEND_SECONDS" ] && [[ "$NANO_PART" =~ ^[0-9]{9}$ ]]; then
                SEND_NS="${SEND_SECONDS}${NANO_PART}"
                RECV_NS=$(now_ns)
                LAT_NS=$((RECV_NS - SEND_NS))
                LAT_MS=$((LAT_NS / 1000000))
                log_result "mqtt_latency" "$LAT_MS"
                echo "Latency: ${LAT_MS} ms"
                echo "------------------------------------------------------"
            else
                echo "ERROR: Could not parse timestamp or invalid nanoseconds: $NANO_PART"
            fi
        else
            echo "ERROR: 'date' command not found"
        fi
    else
        echo "ERROR: No timestamp found in message"
    fi
done