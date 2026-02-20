class compbox::fw_pre {
  Firewall {
    require => undef,
  }

  # Default firewall rules (IPv4)
  firewall { '000 accept all icmp':
    proto     => 'icmp',
    jump      => 'accept',
    protocol  => 'IPv4'
  }->
  firewall { '001 accept all to lo interface':
    proto     => 'all',
    iniface   => 'lo',
    jump      => 'accept',
    protocol  => 'IPv4'
  }->
  firewall { '002 reject local traffic not on loopback interface':
    iniface     => '! lo',
    proto       => 'all',
    destination => '127.0.0.1/8',
    jump        => 'reject',
    protocol    => 'IPv4'
  }->
  firewall { '003 accept related established rules':
    proto     => 'all',
    state     => ['RELATED', 'ESTABLISHED'],
    jump      => 'accept',
    protocol  => 'IPv4'
  }

  # Default firewall rules (IPv6)
  firewall { '000 accept all icmp (v6)':
    proto     => 'ipv6-icmp',
    jump      => 'accept',
    protocol  => 'IPv6',
  }->
  firewall { '001 accept all to lo interface (v6)':
    proto     => 'all',
    iniface   => 'lo',
    jump      => 'accept',
    protocol  => 'IPv6',
  }->
  firewall { '002 reject local traffic not on loopback interface (v6)':
    iniface     => '! lo',
    proto       => 'all',
    destination => '::1',
    jump        => 'reject',
    protocol    => 'IPv6',
  }->
  firewall { '003 accept related established rules (v6)':
    proto     => 'all',
    state     => ['RELATED', 'ESTABLISHED'],
    jump      => 'accept',
    protocol  => 'IPv6',
  }
}
