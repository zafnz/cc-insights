#!/bin/bash
# Test script to simulate progress output like flutter test

for i in {1..5}; do
  printf "\r00:0${i} +0: loading test ${i}..."
  sleep 0.5
done
printf "\n"
echo "Done!"
