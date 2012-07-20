#!/bin/bash

# Poor man's error management :)
set -e


#
# Environment
#

cat > /etc/profile.d/ftc.sh <<"EOF"
alias ll="ls -al"
alias vi="vim"
alias h="history"
alias psu="ps -fu $USER"

if [ "$SHELL" = "/bin/bash" ]
then
    if [[ ${EUID} == 0 ]] ; then
        PS1='\[\033[01;31m\]\h\[\033[01;34m\] \W \$\[\033[00m\] '
    else
        PS1='\[\033[01;32m\]\u@\h\[\033[01;34m\] \w \$\[\033[00m\] '
    fi
fi

export EDITOR=vim

EOF

# cat > /etc/profile.d/proxy.sh <<"EOF"
# export http_proxy=10.28.105.210:1234
# export https_proxy=$http_proxy
# export ftp_proxy=$http_proxy
# export HTTP_PROXY=$http_proxy
# export HTTPS_PROXY=$http_proxy
# export FTP_PROXY=$http_proxy
# EOF

echo 'export RAILS_ENV=production' > /etc/profile.d/rails.sh 

. /etc/profile

#
# Packages
#

yum -y install http://yum.puppetlabs.com/el/6/products/x86_64/puppetlabs-release-6-1.noarch.rpm http://passenger.stealthymonkeys.com/rhel/6/passenger-release.noarch.rpm http://mirror.us.leaseweb.net/epel/6/x86_64/epel-release-6-5.noarch.rpm
yum -y install httpd mod_ssl mod_passenger puppet-server puppet-dashboard mysql-server

#
# Apache
#

echo 'HTTPD=/usr/sbin/httpd.worker' >> /etc/sysconfig/httpd

sed -i -re '
s:^ServerTokens.*:ServerTokens Prod:
s:^User.*:User puppet:
s:^Group.*:Group puppet:
s:^ServerSignature.*:ServerSignature Off:' /etc/httpd/conf/httpd.conf 

grep -qF 'Include vhosts.d/*.conf' /etc/httpd/conf/httpd.conf || echo 'Include vhosts.d/*.conf' >> /etc/httpd/conf/httpd.conf 

mkdir -p /etc/httpd/vhosts.d

cat </etc/httpd/99_mod_passenger.conf <<EOF
PassengerPoolIdleTime 300
PassengerMaxPoolSize 15
PassengerMaxRequests 10000
PassengerUseGlobalQueue on
PassengerHighPerformance on

# ex: set et ts=4 sw=4 ft=apache:
EOF

cat > /etc/httpd/vhosts.d/puppet-master.conf <<EOF
Listen 8140
<VirtualHost *:8140>
    SSLEngine on
    SSLCipherSuite SSLv2:-LOW:-EXPORT:RC4+RSA
    SSLCertificateFile      /var/lib/puppet/ssl/certs/$(hostname -f).pem
    SSLCertificateKeyFile   /var/lib/puppet/ssl/private_keys/$(hostname -f).pem
    SSLCertificateChainFile /var/lib/puppet/ssl/ca/ca_crt.pem
    SSLCACertificateFile    /var/lib/puppet/ssl/ca/ca_crt.pem
    # CRL checking should be enabled; if you have problems with Apache complaining about the CRL, disable the next line
    SSLCARevocationFile     /var/lib/puppet/ssl/ca/ca_crl.pem
    SSLVerifyClient optional
    SSLVerifyDepth  1
    SSLOptions +StdEnvVars

    # The following client headers allow the same configuration to work with Pound.
    RequestHeader set X-SSL-Subject %{SSL_CLIENT_S_DN}e
    RequestHeader set X-Client-DN %{SSL_CLIENT_S_DN}e
    RequestHeader set X-Client-Verify %{SSL_CLIENT_VERIFY}e

    RackAutoDetect On
    DocumentRoot /usr/share/puppet/rack/puppetmasterd/public/
    <Directory /usr/share/puppet/rack/puppetmasterd/>
        Options None
        AllowOverride None
        Order allow,deny
        allow from all
    </Directory>
</VirtualHost>

# ex: set et ts=4 sw=4 ft=apache:
EOF



cat > /etc/httpd/vhosts.d/puppet-dashboard.conf <<EOF
<VirtualHost *:80>
    RackAutoDetect On
    DocumentRoot /usr/share/puppet-dashboard/public/

    # Set the development to serve
    SetEnv RAILS_ENV production

    <Directory /usr/share/puppet-dashboard/public/>
        Options None
        AllowOverride AuthConfig
        Order allow,deny
        Allow from all
    </Directory>
</VirtualHost>

# ex: set et ts=4 sw=4 ft=apache:
EOF


#
# Puppet
#

service puppetmaster start; service puppetmaster stop
mkdir -p /usr/share/puppet/rack/puppetmasterd{,/public,/tmp}
ln -sfn  /usr/share/puppet/ext/rack/files/config.ru /usr/share/puppet/rack/puppetmasterd/config.ru 


#
# mySQL
#

service mysqld start
chkconfig mysqld on
mysql <<"EOF"
CREATE DATABASE dashboard_production CHARACTER SET utf8;
CREATE USER 'dashboard'@'localhost' IDENTIFIED BY 'this.is.the.very.secure.password.for.dashboard';
GRANT ALL PRIVILEGES ON dashboard_production.* TO 'dashboard'@'localhost';
FLUSH PRIVILEGES;
EOF

#
# Dashboard
#

cd /usr/share/puppet-dashboard/
sed -i -re 's/  password:.*/  password: this.is.the.very.secure.password.for.dashboard/' /usr/share/puppet-dashboard/config/database.yml
rake db:migrate
chmod -R ug+rwX /usr/share/puppet* /var/lib/puppet/ /var/log/puppet/
chmod -R ug+rwX /usr/share/puppet* /var/lib/puppet/ /var/log/puppet/
chown -R puppet:puppet /usr/share/puppet/ /var/lib/puppet/ /var/log/puppet/
chown -R puppet-dashboard:puppet-dashboard /usr/share/puppet-dashboard/

service httpd start
chkconfig httpd on


cat >>~/.vimrc <<EOF
set modeline
highlight Comment ctermfg=Green
EOF



exit 0

yum -y install http://yum.theforeman.org/stable/RPMS/foreman-release-1-1.noarch.rpm
yum -y install foreman foreman-proxy



cat > /etc/httpd/vhosts.d/foreman.conf <<EOF
Listen 3000
<VirtualHost *:3000>
    RackAutoDetect On
    DocumentRoot /usr/share/foreman/public/

    # Set the development to serve
    SetEnv RAILS_ENV production

    <Directory /usr/share/foreman/public/>
        Options None
        AllowOverride AuthConfig
        Order allow,deny
        Allow from all
    </Directory>
</VirtualHost>

# ex: set et ts=4 sw=4 ft=apache:
EOF


cat >/usr/lib/ruby/site_ruby/1.8/puppet/reports/foreman.rb <"EOF"
# copy this file to your report dir - e.g. /usr/lib/ruby/1.8/puppet/reports/
# add this report in your puppetmaster reports - e.g, in your puppet.conf add:
# reports=log, foreman # (or any other reports you want)

# URL of your Foreman installation
$foreman_url='http://localhost'

require 'puppet'
require 'net/http'
require 'uri'

Puppet::Reports.register_report(:foreman) do
    Puppet.settings.use(:reporting)
    desc "Sends reports directly to Foreman"

    def process
      begin
        uri = URI.parse($foreman_url)
        http = Net::HTTP.new(uri.host, uri.port)
        if uri.scheme == 'https' then
          http.use_ssl = true
          http.verify_mode = OpenSSL::SSL::VERIFY_NONE
        end
        req = Net::HTTP::Post.new("/reports/create?format=yml")
        req.set_form_data({'report' => to_yaml})
        response = http.request(req)
      rescue Exception => e
        raise Puppet::Error, "Could not send report to Foreman at #{$foreman_url}/reports/create?format=yml: #{e}"
      end
    end
end
EOF


cat > /etc/yum.repos.d/vmware-tools.repo <<"EOF"
[vmware-tools]
name=VMware Tools for Red Hat Enterprise Linux $releasever - $basearch
baseurl=http://packages.vmware.com/tools/esx/4.1latest/rhel$releasever/$basearch
enabled=1
gpgcheck=1
gpgkey=http://packages.vmware.com/tools/VMWARE-PACKAGING-GPG-KEY.pub

EOF


