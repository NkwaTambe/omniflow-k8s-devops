#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e

NAMESPACE="omniflow-dev"
SERVICE="omniflow-frontend"
LOCAL_PORT="8080"
TARGET_PORT="80"
DURATION="30"
CONCURRENCY="100"

echo "=================================================="
echo " OmniFlow Load Testing Script"
echo " Simulating $CONCURRENCY concurrent users for $DURATION seconds"
echo "=================================================="

# Check if port-forwarding is already running on the local port
if lsof -i :$LOCAL_PORT -t >/dev/null; then
  echo "[-] Port $LOCAL_PORT is already in use. Attempting to kill existing process..."
  kill -9 $(lsof -i :$LOCAL_PORT -t) || true
  sleep 1
fi

echo "[+] Starting background port-forwarding for $SERVICE in $NAMESPACE..."
kubectl port-forward -n "$NAMESPACE" svc/"$SERVICE" "$LOCAL_PORT:$TARGET_PORT" > /dev/null 2>&1 &
PF_PID=$!

# Ensure the background port-forwarding process is killed when this script exits
cleanup() {
  echo "[+] Cleaning up background port-forwarding (PID: $PF_PID)..."
  kill $PF_PID 2>/dev/null || true
}
trap cleanup EXIT

echo "[+] Waiting 3 seconds for port-forwarding to establish..."
sleep 3

# Check if the port-forwarding is active
if ! curl -s --connect-timeout 2 http://localhost:$LOCAL_PORT/health > /dev/null; then
  echo "[!] Error: Port-forwarding did not start correctly or application is unhealthy."
  exit 1
fi

echo "[+] Port-forwarding active. Starting load test..."
echo "--------------------------------------------------"
npx autocannon -c "$CONCURRENCY" -d "$DURATION" --latency --renderStatusCodes http://localhost:$LOCAL_PORT/
echo "--------------------------------------------------"
echo "[+] Load test complete."
