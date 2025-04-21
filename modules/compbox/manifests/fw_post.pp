class compbox::fw_post {
  firewall { '999 drop all':
    proto  => 'all',
    jump   => 'drop',
    before => undef,
  }
  firewall { '999 drop all (v6)':
    proto     => 'all',
    jump      => 'drop',
    before    => undef,
    protocol  => 'ip6tables',
  }
}
