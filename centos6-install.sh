#!/bin/bash

# Poor man's error management :)
set -e

RPM_PACKAGES=""

# General
RPM_PACKAGES="${RPM_PACKAGES} httpd"
RPM_PACKAGES="${RPM_PACKAGES} mod_ssl"
RPM_PACKAGES="${RPM_PACKAGES} mysql-server"
RPM_PACKAGES="${RPM_PACKAGES} mod_passenger"

# Puppet
RPM_PACKAGES="${RPM_PACKAGES} puppet-server"
RPM_PACKAGES="${RPM_PACKAGES} puppet-dashboard" # Optional

# Foreman - (un)comment as needed
RPM_PACKAGES="${RPM_PACKAGES} foreman"
RPM_PACKAGES="${RPM_PACKAGES} foreman-cli"
RPM_PACKAGES="${RPM_PACKAGES} foreman-console"
RPM_PACKAGES="${RPM_PACKAGES} foreman-ec2"
#RPM_PACKAGES="${RPM_PACKAGES} foreman-fog"
#RPM_PACKAGES="${RPM_PACKAGES} foreman-libvirt"

# We use rubygem-mysql2. See: 
# http://stackoverflow.com/questions/5411551/what-the-difference-between-mysql-and-mysql2-gem
#RPM_PACKAGES="${RPM_PACKAGES} foreman-mysql"
RPM_PACKAGES="${RPM_PACKAGES} foreman-mysql2"

#RPM_PACKAGES="${RPM_PACKAGES} foreman-ovirt"
#RPM_PACKAGES="${RPM_PACKAGES} foreman-postgresql"
RPM_PACKAGES="${RPM_PACKAGES} foreman-proxy"
#RPM_PACKAGES="${RPM_PACKAGES} foreman-sqlite"
# Obsoletted by libvirt above
#RPM_PACKAGES="${RPM_PACKAGES} foreman-virt"
RPM_PACKAGES="${RPM_PACKAGES} foreman-vmware"


YUM_REPOS=""
YUM_REPOS="${YUM_REPOS} http://yum.puppetlabs.com/el/6/products/x86_64/puppetlabs-release-6-1.noarch.rpm"
YUM_REPOS="${YUM_REPOS} http://passenger.stealthymonkeys.com/rhel/6/passenger-release.noarch.rpm"
YUM_REPOS="${YUM_REPOS} http://mirror.us.leaseweb.net/epel/6/x86_64/epel-release-6-5.noarch.rpm"
YUM_REPOS="${YUM_REPOS} http://yum.theforeman.org/releases/latest/el6/x86_64/foreman-release.rpm"


#
# Packages
#
function set_repos() {
  test -z "${YUM_REPOS}" || yum install -y ${YUM_REPOS}

  cat > /etc/yum.repos.d/vmware-tools.repo <<"EOF"
[vmware-tools]
name=VMware Tools for Red Hat Enterprise Linux $releasever - $basearch
baseurl=http://packages.vmware.com/tools/esx/4.1latest/rhel$releasever/$basearch
enabled=1
gpgcheck=1
gpgkey=http://packages.vmware.com/tools/VMWARE-PACKAGING-GPG-KEY.pub

EOF

}

function install_packages() {
  test -z "${RPM_PACKAGES}" || yum install -y ${RPM_PACKAGES}
}


#
# Environment
#

function set_profile() {

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

  source /etc/profile
}

function set_proxy() {
  cat > /etc/profile.d/proxy.sh <<"EOF"
export http_proxy=10.28.105.210:1234
export https_proxy=$http_proxy
export ftp_proxy=$http_proxy
export HTTP_PROXY=$http_proxy
export HTTPS_PROXY=$http_proxy
export FTP_PROXY=$http_proxy
EOF

  source /etc/profile
}

function set_rails_env() {

  echo 'export RAILS_ENV=production' > /etc/profile.d/rails.sh 

  source /etc/profile
}

#
# mySQL
#
function setup_mysql() {

  service mysqld start
  chkconfig mysqld on

  mysql <<"EOF"
CREATE DATABASE IF NOT EXISTS dashboard_production CHARACTER SET utf8;
GRANT ALL PRIVILEGES ON dashboard_production.* TO 'dashboard'@'localhost' IDENTIFIED BY 'this.is.a.not.very.secure.password.for.dashboard';
CREATE DATABASE IF NOT EXISTS puppet CHARACTER SET utf8;
GRANT ALL PRIVILEGES ON puppet.* TO 'puppet'@'localhost' IDENTIFIED BY 'this.is.a.not.very.secure.password.for.puppet';
FLUSH PRIVILEGES;
EOF
}


#
# Apache
#
function configure_apache() {

  # Remove the annoying default vhost
  test -f /etc/httpd/conf.d/welcome.conf && rm -f /etc/httpd/conf.d/welcome.conf
  # Remove the default SSL vhost
  sed -i '/^Listen/d; /<VirtualHost/,/<\/VirtualHost/d' /etc/httpd/conf.d/ssl.conf

  echo 'HTTPD=/usr/sbin/httpd.worker' >> /etc/sysconfig/httpd

  sed -i -re '
  s:^ServerTokens.*:ServerTokens Prod:
  s:^User.*:User puppet:
  s:^Group.*:Group puppet:
  s:^ServerSignature.*:ServerSignature Off:' /etc/httpd/conf/httpd.conf 

  grep -qF 'Include vhosts.d/*.conf' /etc/httpd/conf/httpd.conf || echo 'Include vhosts.d/*.conf' >> /etc/httpd/conf/httpd.conf 

  mkdir -p /etc/httpd/vhosts.d

  cat >/etc/httpd/conf.d/99_mod_passenger.conf <<EOF
PassengerPoolIdleTime 300
PassengerMaxPoolSize 15
PassengerMaxRequests 10000
PassengerUseGlobalQueue on
PassengerHighPerformance on

# ex: set et ts=4 sw=4 ft=apache:
EOF

  service httpd start
  chkconfig httpd on

}

function puppet_vhost() {

  mkdir -p /usr/share/puppet/rack/puppetmasterd{,/public,/tmp}
  ln -sfn  /usr/share/puppet/ext/rack/files/config.ru /usr/share/puppet/rack/puppetmasterd/config.ru 

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
}

function dashboard_vhost() {
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
}

function foreman_vhost() {
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
}

#
# Puppet CA
#

function init_puppet_ca() {
  # Just start & stop the stand alone puppet master
  # If the CA/SSL don't exist yet, it will create them
  service puppetmaster start; service puppetmaster stop
}

#
# Dashboard
#

function config_foreman() {

  cat > /etc/foreman/database.yml <<EOF
production:
  adapter: mysql
  database: puppet
  username: puppet
  password: this.is.a.not.very.secure.password.for.puppet
  host: localhost
  socket: "/var/lib/mysql/mysql.sock"
EOF

  su - foreman -s /bin/bash -c /usr/share/foreman/extras/dbmigrate
}

function init_dashboard_db() {

  cd /usr/share/puppet-dashboard/
  sed -i -re 's/  password:.*/  password: this.is.a.not.very.secure.password.for.dashboard/' /usr/share/puppet-dashboard/config/database.yml
  rake db:migrate
}

function fix_perms() {
  chmod -R ug+rwX /usr/share/puppet* /var/lib/puppet/ /var/log/puppet/
  chown -R puppet:puppet /usr/share/puppet/ /var/lib/puppet/ /var/log/puppet/
  chown -R puppet-dashboard:puppet-dashboard /usr/share/puppet-dashboard/
}

function config_dashboard() {
  grep -q ^time_zone /usr/share/puppet-dashboard/config/settings.yml || echo "time_zone: 'London'" >> /usr/share/puppet-dashboard/config/settings.yml
  sed -i -re "
    s/^enable_inventory_service:.*/enable_inventory_service: true/;
    s/^inventory_server:.*/inventory_server: 'localhost'/;
    s/^use_file_bucket_diffs:.*/use_file_bucket_diffs: true/;
    s/^file_bucket_server:.*/file_bucket_server: 'localhost'/;
    s/^use_external_node_classification:.*/use_external_node_classification: false/;
    s/^enable_read_only_mode:.*/enable_read_only_mode: true/;
    s/^time_zone:.*/time_zone: 'London'/;
  " /usr/share/puppet-dashboard/config/settings.yml
}


#set_profile
#set_proxy
set_rails_env

#set_repos
install_packages

setup_mysql
configure_apache

puppet_vhost
dashboard_vhost
foreman_vhost
init_dashboard_db
init_puppet_ca
config_dashboard
config_foreman


exit 0

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

