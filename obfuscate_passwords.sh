#!/bin/bash

echo -n "Enter the password to obfuscate:"
read password
cd /var/log/change_password/
echo "Starting obfuscation of clear-text passwords..."
find /var/log/change_password/*.log -type f -exec sed -i "s/PASSWORD('.*')/PASSWORD('********')/g" {} \;
find /var/log/change_password/*.log -type f -exec sed -i "s/$password/********/g" {} \;
echo "Finished!"
