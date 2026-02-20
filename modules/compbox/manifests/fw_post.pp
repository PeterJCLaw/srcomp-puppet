class compbox::fw_post {
  firewall { '999 drop all':
    proto     => 'all',
    jump      => 'drop',
    before    => undef,
    protocol  => 'IPv4'
  }
  firewall { '999 drop all (v6)':
    proto     => 'all',
    jump      => 'drop',
    before    => undef,
    protocol  => 'IPv6',
  }
}
