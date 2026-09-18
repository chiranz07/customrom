#!/bin/bash
cd ~/voltage/vendor/voltage-priv/keys || exit 1
./keys.sh > ~/voltage_keys.log 2>&1 && echo "KEYS_OK $(date)" || { echo "KEYS_FAILED $(date)"; exit 1; }
echo "certs: $(ls *.x509.pem | wc -l), bp entries: $(grep -c android_app_certificate Android.bp)"
bash ~/launch_voltage.sh shiba voltage_shiba-cp2a-userdebug bacon
echo "RELAUNCHED $(date)"
