class compbox::firewall {
  class { 'firewall': }

  resources { 'firewall':
    purge => true,
  }

  Firewall {
    before  => Class['compbox::fw_post'],
    require => Class['compbox::fw_pre'],
  }

  class { ['compbox::fw_pre', 'compbox::fw_post']: }

  # SSH
  firewall { '100 allow ssh access':
    dport  => 22,
    proto  => tcp,
    action => accept,
  }
  firewall { '100 allow ssh access (v6)':
    dport     => 22,
    proto     => tcp,
    action    => accept,
    provider  => 'ip6tables',
  }

  # NTP
  firewall { '100 allow ntp access':
    dport  => 123,
    proto  => udp,
    action => accept,
  }
  firewall { '100 allow ntp access (v6)':
    dport     => 123,
    proto     => udp,
    action    => accept,
    provider  => 'ip6tables',
  }

  # HTTP(S)
  firewall { '100 allow http and https access':
    dport  => [80, 443],
    proto  => tcp,
    action => accept,
  }
  firewall { '100 allow http and https access (v6)':
    dport     => [80, 443],
    proto     => tcp,
    action    => accept,
    provider  => 'ip6tables',
  }

  # Mythic Beasts
  firewall { '200 allow Mythic Beasts\' munin monitoring access (v6)':
    dport     => 4949,
    source    => '2a00:1098:0:80:1000::100',
    proto     => tcp,
    action    => accept,
    provider  => 'ip6tables',
  }
}
