#!/bin/bash
# this script is a modified version of what Chia-Chin Chung <60947091s@gapps.ntnu.edu.tw> wrote for oqs-demos/mosquitto

########## functions ##########
cleanup() {
    echo "------------------------------------------------------"
    echo "Cleaning up..."
    sudo gpioset $GPIO_CHIP $LED_STATUS_PIN=0
    sudo gpioset $GPIO_CHIP $LED_DETECT_PIN=0
    echo "GPIO cleaned up"
    echo "------------------------------------------------------"
    exit 0
}

########## initialization ##########

# define the motion sensor circuit config vars
GPIO_CHIP="gpiochip0"  # RP1 chip on Pi 5
MOTION_PIN=14          # BCM14 - Physical pin 8
LED_DETECT_PIN=20      # BCM20 - Physical pin 38
LED_STATUS_PIN=21      # BCM21 - Physical pin 40

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
read -p "Enter publisher IP address: " PUB_IP
PUB_IP=${PUB_IP:-localhost}
echo "------------------------------------------------------"

# generate the publisher PQC certificates; suppress output
openssl req -new -newkey $SIG_ALG -keyout /pqc-mqtt/cert/publisher.key -out /pqc-mqtt/cert/publisher.csr -nodes -subj "/O=pqc-mqtt-publisher/CN=$PUB_IP" > /dev/null 2>&1
openssl x509 -req -in /pqc-mqtt/cert/publisher.csr -out /pqc-mqtt/cert/publisher.crt -CA /pqc-mqtt/cert/CA.crt -CAkey /pqc-mqtt/cert/CA.key -CAcreateserial -days 365 > /dev/null 2>&1
chmod 777 /pqc-mqtt/cert/* 2>/dev/null || true

# initialize the motion sensor
echo "Certificates generated successfully."
echo "Starting motion sensor monitor..."
echo "Initial motion sensor reading:"
initial_state=$(sudo gpioget $GPIO_CHIP $MOTION_PIN)
echo "GPIO$MOTION_PIN = $initial_state"
echo "------------------------------------------------------"

# turn on the status LED 
sudo gpioset $GPIO_CHIP $LED_STATUS_PIN=1
echo "Status LED: ON (GPIO$LED_STATUS_PIN)"
echo "Watching for motion on GPIO$MOTION_PIN..."
echo "Press Ctrl+C to stop"
echo "------------------------------------------------------"

# state machine vars
last_state="0"
first_run=true

# setup trap for cleanup
trap cleanup INT TERM EXIT

# infinite (until terminated) motion sensor loop
while true; do
    current_state=$(sudo gpioget $GPIO_CHIP $MOTION_PIN 2>/dev/null || echo "error")
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # check if the pins can be read
    if [ "$current_state" = "error" ]; then
        echo "[$timestamp]  : ERROR - cannot read GPIO$MOTION_PIN"
        sleep 2
        continue
    fi
    
    if [ "$first_run" = true ] && [ "$current_state" = "1" ]; then
        echo "[$timestamp]  :   Motion detected."
        
        # turn on the detection LED 
        sudo gpioset $GPIO_CHIP $LED_DETECT_PIN=1
        sleep 0.25
        sudo gpioset $GPIO_CHIP $LED_DETECT_PIN=0
        
        # publish the message via MQTT using mosquitto package
        message="[$timestamp]  :   Motion detected."
        mosquitto_pub -h $BROKER_IP -m "$message" -t "pqc-mqtt-sensor/motion-sensor" -q 0 -i "MotionSensor_pub" \
            --tls-version tlsv1.3 --cafile /pqc-mqtt/cert/CA.crt \
            --cert /pqc-mqtt/cert/publisher.crt --key /pqc-mqtt/cert/publisher.key 2>/dev/null && \
            echo "[$timestamp]  :   Info successfully sent to broker."
        
        first_run=false
        last_state="1"
        sleep 1
        
    elif [ "$current_state" = "1" ] && [ "$last_state" = "0" ]; then
        echo "[$timestamp]  :   Motion detected."
        
        # Blink detection LED
        sudo gpioset $GPIO_CHIP $LED_DETECT_PIN=1
        sleep 0.25
        sudo gpioset $GPIO_CHIP $LED_DETECT_PIN=0
        
        # Publish to MQTT
        message="[$timestamp]  :   Motion detected."
        if mosquitto_pub -h $BROKER_IP -m "$message" -t "pqc-mqtt-sensor/motion-sensor" -q 0 -i "MotionSensor_pub" \
            --tls-version tlsv1.3 --cafile /pqc-mqtt/cert/CA.crt \
            --cert /pqc-mqtt/cert/publisher.crt --key /pqc-mqtt/cert/publisher.key 2>/dev/null; then
            echo "[$timestamp]  :   Info successfully sent to broker."
        else
            echo "[$timestamp]  :   Info failed to send to broker."
        fi
        
        last_state="1"
        sleep 1  
        
    elif [ "$current_state" = "0" ]; then
        if [ "$first_run" = true ]; then
            first_run=false
        fi
        last_state="0"
        
    elif [ "$current_state" = "1" ] && [ "$last_state" = "1" ]; then
        # continuous motion; do nothing
        :
    fi
    
    # publish a heartbeat every 60 seconds 
    current_time=$(date +%s)
    if [ -z "$last_heartbeat" ] || [ $((current_time - last_heartbeat)) -ge 60 ]; then
        heartbeat_msg="[$timestamp]  :   sensor heartbeat on $MOTION_PIN"
        echo "[$timestamp]  :   sensor heartbeat"
        
        mosquitto_pub -h $BROKER_IP -m "$heartbeat_msg" -t "pqc-mqtt-sensor/status" -q 0 -i "MotionSensor_pub" \
            --tls-version tlsv1.3 --cafile /pqc-mqtt/cert/CA.crt \
            --cert /pqc-mqtt/cert/publisher.crt --key /pqc-mqtt/cert/publisher.key 2>/dev/null
        
        last_heartbeat=$current_time
    fi
    
    sleep 0.25
done