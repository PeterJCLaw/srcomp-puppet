# Set the hostname on the Pis so that they can easily be identified when
# shelling in

class compbox::hostname ( $hostname = hiera('hostname') ) {

  if $facts['fqdn'] != $hostname {
    host { $facts['fqdn']:
      ensure  => absent,
      before  => Exec['hostnamectl'],
    }

    if $facts['fqdn'] != $facts['hostname'] {
      host { $facts['hostname']:
        ensure  => absent,
        before  => Exec['hostnamectl'],
      }
    }

    host { 'custom fqdn':
      ensure  => present,
      name    => $hostname,
      ip      => '127.0.1.1',
      before  => Exec['hostnamectl'],
    }

    file { '/etc/hostname':
      ensure  => present,
      owner   => 'root',
      group   => 'root',
      mode    => '0644',
      content => "${hostname}\n",
      notify  => Exec['hostnamectl'],
    }

    exec { 'hostnamectl':
      command     => "/usr/bin/hostnamectl set-hostname $hostname",
      refreshonly => true,
    }
  }
}
