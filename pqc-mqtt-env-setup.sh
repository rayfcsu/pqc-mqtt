#!/bin/bash

# this script is a modified version of Chia-Chin Chung <60947091s@gapps.ntnu.edu.tw> wrote for oqs-demos/mosquitto
# originally a docker file and converted to a bash script

set -e  # Exit on any error

# configuration variables
OPENSSL_TAG="openssl-3.4.0"
LIBOQS_TAG="0.13.0"
OQSPROVIDER_TAG="0.9.0"
INSTALLDIR="/opt/oqssa"
LIBOQS_BUILD_DEFINES="-DOQS_DIST_BUILD=ON"
KEM_ALGLIST="mlkem768:p384_mlkem768"
SIG_ALG="falcon1024"
MOSQUITTO_TAG="v2.0.20"

# set timezone
export TZ="America/New_York"
export DEBIAN_FRONTEND=noninteractive

# update system and install prerequisites
echo "Updating system and installing prerequisites..."
apt update && apt install -y build-essential \
    cmake \
    gcc \
    libtool \
    libssl-dev \
    make \
    ninja-build \
    git \
    doxygen \
    libcjson1 \
    libcjson-dev \
    uthash-dev \
    libcunit1-dev \
    libsqlite3-dev \
    xsltproc \
    docbook-xsl \
    openssh-client \
    gpiod

# create installation directory
mkdir -p $INSTALLDIR

# get all sources
echo "Downloading source code..."
cd /opt
git clone --depth 1 --branch $LIBOQS_TAG https://github.com/open-quantum-safe/liboqs
git clone --depth 1 --branch $OPENSSL_TAG https://github.com/openssl/openssl.git
git clone --depth 1 --branch $OQSPROVIDER_TAG https://github.com/open-quantum-safe/oqs-provider.git
git clone --depth 1 --branch $MOSQUITTO_TAG https://github.com/eclipse/mosquitto.git

# build liboqs
echo "Building liboqs..."
cd /opt/liboqs
mkdir -p build && cd build
cmake -G"Ninja" .. $LIBOQS_BUILD_DEFINES -DCMAKE_INSTALL_PREFIX=$INSTALLDIR
ninja install

# build openssl
echo "Building OpenSSL..."
cd /opt/openssl
LDFLAGS="-Wl,-rpath -Wl,${INSTALLDIR}/lib64" ./config shared --prefix=$INSTALLDIR
make -j $(nproc)
make install_sw install_ssldirs

# create lib64/lib symlinks if needed
if [ -d ${INSTALLDIR}/lib64 ]; then
    ln -sf ${INSTALLDIR}/lib64 ${INSTALLDIR}/lib
fi
if [ -d ${INSTALLDIR}/lib ]; then
    ln -sf ${INSTALLDIR}/lib ${INSTALLDIR}/lib64
fi

# update PATH
export PATH="${INSTALLDIR}/bin:${PATH}"

# build and install oqsprovider
echo "Building oqs-provider..."
cd /opt/oqs-provider
ln -sf ../openssl .
cmake -DOPENSSL_ROOT_DIR=$INSTALLDIR -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH=$INSTALLDIR -S . -B _build
cmake --build _build
cp _build/lib/oqsprovider.so ${INSTALLDIR}/lib64/ossl-modules

# configure openssl.cnf
echo "Configuring OpenSSL..."
OPENSSL_CNF="${INSTALLDIR}/ssl/openssl.cnf"
if [ -f "$OPENSSL_CNF" ]; then
    sed -i "s/default = default_sect/default = default_sect\noqsprovider = oqsprovider_sect/g" "$OPENSSL_CNF"
    sed -i "s/\[default_sect\]/\[default_sect\]\nactivate = 1\n\[oqsprovider_sect\]\nactivate = 1\n/g" "$OPENSSL_CNF"
    sed -i "s/providers = provider_sect/providers = provider_sect\nssl_conf = ssl_sect\n\n\[ssl_sect\]\nsystem_default = system_default_sect\n\n\[system_default_sect\]\nGroups = ${KEM_ALGLIST}\n/g" "$OPENSSL_CNF"
fi

# build and install Mosquitto
echo "Building Mosquitto..."
cd /opt/mosquitto
make -j$(nproc)
make install

# install runtime dependencies
echo "Installing runtime dependencies..."
apt update && apt install -y libcjson1

# set environment variables
export SIG_ALG=$SIG_ALG
export BROKER_IP=$BROKER_IP
export PUB_IP=$PUB_IP
export SUB_IP=$SUB_IP
export EXAMPLE=$EXAMPLE
export TLS_DEFAULT_GROUPS=$KEM_ALGLIST
export LD_LIBRARY_PATH=$INSTALLDIR/lib64
export PATH="/usr/local/bin:/usr/local/sbin:${INSTALLDIR}/bin:$PATH"

# create mosquitto library symlink and update ldconfig
echo "Setting up library links..."
ln -sf /usr/local/lib/libmosquitto.so.1 /usr/lib/libmosquitto.so.1
ldconfig

# create test directory and copy test files (assuming current directory has test files)
echo "Setting up environment..."
mkdir -p /pqc-mqtt

# copy only regular files from current directory to /test
echo "Copying test files..."
if [ -d "./pqc-mqtt-files" ]; then
    cp -r ./pqc-mqtt-files/* /pqc-mqtt/ 2>/dev/null || true
else
    # copy only regular files, not directories
    find . -maxdepth 1 -type f -exec cp {} /pqc-mqtt/ \; 2>/dev/null || true
    
    # copy specific directories if they exist
    [ -d "./scripts" ] && cp -r ./scripts /pqc-mqtt/ 2>/dev/null || true
    [ -d "./config" ] && cp -r ./config /pqc-mqtt/ 2>/dev/null || true
fi

# fix line endings only for text files
echo "Fixing line endings for script files..."
find /pqc-mqtt -type f -name "*.sh" -exec sed -i 's/\r//' {} \; 2>/dev/null || true
find /pqc-mqtt -type f -name "*.txt" -exec sed -i 's/\r//' {} \; 2>/dev/null || true
find /pqc-mqtt -type f -name "*.conf" -exec sed -i 's/\r//' {} \; 2>/dev/null || true

# set executable permissions only for script files
echo "Setting executable permissions..."
find /pqc-mqtt -type f -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true

echo "-----------------------------------------"
echo "=== Setup completed successfully! ==="
echo "MQTTS port 8883 is available for use"
echo "-----------------------------------------"