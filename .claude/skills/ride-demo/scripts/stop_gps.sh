#!/bin/bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
pkill -f "simctl location" 2>/dev/null
for K in $(keys); do xcrun simctl location "$(udid_for "$K")" clear 2>/dev/null; done
echo "GPS cleared on all devices"
