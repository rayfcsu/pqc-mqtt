#!/bin/bash

RUNS=25
ALGS=("rsa" "falcon1024")

for ALG in "${ALGS[@]}"; do
    export PQC_ALG=$ALG
    echo "testing $ALG"

    for i in $(seq 1 $RUNS); do
        echo "Run $i / $RUNS"
        sudo PQC_ALG=$ALG ./publisher-start.sh
        sleep 0.2
    done
done