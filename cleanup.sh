#!/bin/bash

yum erase $(rpm -qa|egrep "(httpd|passenger|foreman|facter|puppet|bind|dhcp)"|egrep -v "bind-(utils|libs)|dhcp(-common|client)")  && \
yum erase $(rpm -qa '*ruby*') && \
rm -rf /usr/lib*/ruby /var/*/{puppet,foreman,dhcpd}* /usr/share/{puppet,foreman}* /etc/{bind,dhcp,named,httpd,puppet,foreman}* /var/spool/cron/foreman /var/run/rubygem-passenger /etc/sudoers.d/foreman-proxy  /etc/sysconfig/foreman* /var/named /etc/rndc.key /etc/sysconfig/dhcpd* && \
updatedb && \
locate  --regex "(puppet|ruby|foreman|bind|named|dhcp|rndc)"|egrep -v "yum|vim|depot|/root|selinux|/mc/|augeas|/etc/pki/rpm-gpg/"

