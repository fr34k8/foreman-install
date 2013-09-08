#! /usr/bin/env puppet apply --modulepath /root/src/foreman-installer/ 

file { '/etc/httpd/vhost.d':
  ensure => directory,
} ->

class {'apache': 
} ->

class {'passenger':
} ->

class {'puppet':
} ->

class {'puppet::server':
  git_repo => false,
} ->

class {'foreman_proxy':
  dhcp => true,
  dhcp_gateway => '172.16.61.1',
  dhcp_range => '172.16.61.100 172.16.61.200',
  dhcp_nameservers => '172.16.61.1, 87.194.255.154, 87.194.255.155, 216.244.192.2, 216.244.192.3',
  dns  => true,
  dns_reverse => '61.16.172.in-addr.arpa',
} ->

class {'foreman':
  storeconfigs   => true,
  authentication => false,
  use_sqlite     => true,
}

