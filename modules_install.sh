#!/bin/bash

MODULE_DIR="/etc/puppet/modules/external"

MODULES=""
MODULES="${MODULES} puppetlabs-stdlib"
MODULES="${MODULES} puppetlabs-firewall"
MODULES="${MODULES} puppetlabs-apache"
MODULES="${MODULES} puppetlabs-dashboard"
MODULES="${MODULES} puppetlabs-git"
MODULES="${MODULES} puppetlabs-mcollective"
MODULES="${MODULES} puppetlabs-motd"
MODULES="${MODULES} puppetlabs-mysql"
MODULES="${MODULES} puppetlabs-ntp"
MODULES="${MODULES} puppetlabs-puppetdb"

mkdir -p "${MODULE_DIR}" || exit 1

for module in ${MODULES} 
do 
  puppet module install --target-dir "${MODULE_DIR}" ${module}
done

