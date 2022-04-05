#!/usr/bin/env bash

tail -f ./data/info.log &

echo 'Running Product Tracker..'
./src/main.sh
