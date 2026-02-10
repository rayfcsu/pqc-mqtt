# PQC MQTT Motion Sensor System

A post-quantum cryptography (PQC) secured implementation of Raspberry Pi-powered MQTT sensor system. More specifically, it utilizes the falcon1024 signing algorithm for all MQTT communications.

This repo expands upon the work found here: https://github.com/open-quantum-safe/oqs-demos/tree/main/mosquitto. Rather than implementing a simple MQTT test with the pre-built Docker file, this repo implements a motion detection system via modified versions of the provided bash scripts. 

## Background

This repo implements a secure IoT motion sensor system using:
- **Post-Quantum Cryptography (PQC)**: Cryptography algorithms created to withstand predicted PQC decryption 
- **MQTT Protocol**: Lightweight messaging protocol used in IoT applications
- **TLS 1.3**: Secure communication with PQC cipher suites

## Design
The system consists of three main components:
1. **Broker**: MQTT broker terminal that facillitates communications between the publisher and subscriber nodes
2. **Publisher**: Publisher terminal with an attached PIR motion sensor that detects and publishes motion events
3. **Subscriber**: Client terminal that receives and displays detection notifications

All three connect via PQC certificates to one another. 

## Prerequisites
You must have the following at your disposal to fully setup the PQC MQTT motion detection system:
- 3 Raspberry Pi 5's
- A breadboard
- An HC-SR501 PIR motion sensor
- 3 female-female jumper wires
- 3 female-male jumper wires
- 2 220 or 300 ohm resistors
- 2 LEDs

You must have SSH configured on each Raspberry Pi as well as its respective local IP address.

## Setup

### 1. Environment Preparation

Run the main setup script to install all dependencies and build the PQC-enabled components:

```bash
chmod +x pqc-mqtt-env-setup.sh && \
sudo ./pqc-mqtt-env-setup.sh
```

This script:
- Installs system dependencies 
- Downloads and builds liboqs, openssl, oqs-provider, and mosqiutto
- Sets environment variables and library paths
- Creates the /pqc-mqtt working directory 

After that, setup the motion detection system circuit the same as below: 
<img width="650" height="523" alt="image" src="https://github.com/user-attachments/assets/58192b06-5e54-4f2a-8e36-020e1fc291fa" />

*Source: https://opensource.com/article/20/11/motion-detection-raspberry-pi*

Finally, export your IP address configurations to a file named pqc-env.sh. This is referenced in the setup scripts for the broker, subscriber, and publisher as to avoid repeated entry of the data. Configure it like so:

```
export BROKER_IP=<broker_ip>
export PUB_IP=<publisher_ip>
export SUB_IP=<subscriber_ip>
```

This file in the repository is ignored by default. 

### 2. Certificate Authority (CA) & Broker Setup

Start the broker to generate CA certificates and configure the MQTT server:
```bash
chmod +x broker-start.sh && \
sudo ./broker-start.sh
```

The script will:
- Generate CA key and certificate using Falcon-1024
- Copy the CA certificate and key to the publisher and subscriber nodes
- Generate the broker certificate
- Create the Mosquitto configuration file with PQC TLS settings
- Set up authentication (username/password and certificate-based)
- Start the Mosquitto broker on port 8883

### 3. Publisher (Motion Sensor) Setup

On the Raspberry Pi with the motion sensor connected:
```bash
chmod +x publisher-start.sh && \
sudo ./publisher-start.sh
```

Hardware Configuration (default):
- Motion Sensor: GPIO14 (BCM14, Physical pin 8)
- Status LED: GPIO21 (BCM21, Physical pin 40)
- Detection LED: GPIO20 (BCM20, Physical pin 38)

Note that these configurations are based on the ones described in section 1. If any pins are changed, then the script will fail to recognize the sensor.

The publisher will:
- Generate its PQC certificate using the CA
- Initialize GPIO pins for motion sensor and LEDs
- Monitor for motion detection
- Publish motion events to the pqc-mqtt-sensor/motion-sensor topic
- Send heartbeat messages every 60 seconds to pqc-mqtt-sensor/status

### 4. Subscriber Setup

On the Raspberry Pi that should receive the motion notifications:
```bash
chmod +x subscriber-start.sh && \
sudo ./subscriber-start.sh
```

The subscriber will:
- Generate its PQC certificate using the CA
- Connect to the broker with PQC-secured TLS 1.3
- Subscribe to the motion sensor topic
- Display real-time motion notifications

### 5. Testing

On both the subscriber and publisher, there are scripts that allow for simple testing of certificate generation time complexity. To run such tests, execute the appropriate script for its respective node (i.e. running run-publisher-tests.sh on the publisher device). 

All collected data is output to a CSV in the ```~/pqc-mqtt``` working directory called 'results.csv'. Because Mosquitto is a persistent service, to test the time complexity, one must terminate each session after it successfully completes the certificate generation of the *-start* script. This is sufficient enough for gathering details on time spent, however.

## Cleanup
To completely remove the PQC/MQTT installation and clean up all files:
```bash
chmod +x pqc-mqtt-env-cleanup.sh && \
sudo ./pqc-mqtt-env-cleanup.sh
```

This script will:
- Remove installation directories (/opt/oqs-*, /opt/liboqs, /opt/openssl, /opt/oqssa, /opt/mosquitto)
- Remove project directory (/pqc-mqtt)
- Remove Mosquitto binaries and libraries
- Remove symbolic links

**Warning: This cleanup is irreversible and will remove all certificates and configuration files.**

## Script Details
### pqc-mqtt-env-setup.sh
Main installation script that builds all PQC components from source.

### broker-start.sh
Broker initialization script that generates CA certificates, configures Mosquitto, and starts the broker.

### publisher-start.sh
Motion sensor system.

### subscriber-start.sh
MQTT subscriber client for receiving motion notifications.

### pqc-mqtt-env-cleanup.sh
Complete cleanup script for removing all PQC/MQTT components.

### run-subscriber-tests.sh
Script that iteratively tests the certificate generation time for the subscriber node.

### run-publisher-tests.sh
Script that iteratively tests the certificate generation time for the publisher node. 

## Files and Directories

- **/opt/oqssa/** - Main PQC installation directory
- **/pqc-mqtt/** - Test files and certificates
- **/pqc-mqtt/cert/** - CA and device certificates
- **/usr/local/bin/mosquitto** - MQTT binaries


