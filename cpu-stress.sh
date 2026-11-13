#!/bin/bash
# Short CPU stress to trigger the CPUUtilization > 70% alarm. Always bounded by timeout.
# Needs: sudo apt-get install -y stress
set -e
echo "Starting 6-minute CPU stress (stops automatically)..."
timeout 360 stress --cpu 2 --timeout 360 || true
echo "Stress finished. Confirm CPU has dropped in CloudWatch."
