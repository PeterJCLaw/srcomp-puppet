# Install and configure the services running on the compbox
class compbox {
    $comp_source    = 'https://github.com/PeterJCLaw'
    $compstate      = 'https://github.com/PeterJCLaw/dummy-comp.git'
    $compstate_path = '/srv/state'

    $track_source = false

    if $track_source {
        $vcs_ensure = 'latest'
    } else {
        $vcs_ensure = 'present'
    }

    define systemd_service($command,
                           $user,
                           $desc,
                           $dir = undef,
                           $depends = ['network.target'],
                           $subs = []) {
        $service_name = "${title}.service"
        $service_file = "/etc/systemd/system/${service_name}"

        $service_description = $desc
        $start_dir = $dir
        $start_command = $command
        $depends_str = join($depends, ' ')

        file { $service_file:
            ensure  => present,
            owner   => 'root',
            group   => 'root',
            mode    => '0644',
            content => template('compbox/service.erb'),
        } ->
        file { "/etc/systemd/system/multi-user.target.wants/${service_name}":
            ensure  => link,
            target  => $service_file,
        } ->
        exec { "${title}-systemd-load":
            provider  => 'shell',
            command   => 'systemctl daemon-reload',
            onlyif    => "systemctl --all | grep -F ${service_name}; if test $? = 0; then exit 1; fi; exit 0",
            subscribe => File[$service_file],
        } ->
        service { $title:
            ensure    => running,
            enable    => true,
            subscribe => union([File[$service_file]], $subs),
        }
    }

    define npm_install($ensure) {
        $package_name = $title
        if $manual_npm_installs {
            if $ensure == 'absent'{
                exec { "npm uninstall -g ${package_name}":
                    onlyif      => "npm list -depth 0 -g ${package_name}",
                    require     => Class['::nodejs'],
                    provider    => 'shell',
                }
            } else {
                exec { "npm install -g ${package_name}":
                    unless      => "npm list -depth 0 -g ${package_name}",
                    require     => Class['::nodejs'],
                    provider    => 'shell',
                }
            }
        } else {
            package { 'bower':
                ensure      => $ensure,
                provider    => 'npm',
                require     => Class['::nodejs'],
            }
        }
    }

    exec { 'update package lists':
        command => '/usr/bin/apt-get update',
        before  => [Package['libyaml-dev']],
    }

    class { 'compbox::firewall': }

    # A user for shelling in to update the compstate
    user { 'srcomp':
        ensure      => present,
        comment     => 'Competition Software Owner',
        gid         => 'users',
        managehome  => true,
        shell       => '/bin/bash',
    }

    $srcomp_home_dir = '/home/srcomp'
    $ref_compstate = "${srcomp_home_dir}/compstate.git"
    $srcomp_ssh_dir = "${srcomp_home_dir}/.ssh"

    file { $srcomp_ssh_dir:
        ensure  => directory,
        owner   => 'srcomp',
        group   => 'users',
        mode    => '0700',
        require => User['srcomp'],
    }

    file { "${srcomp_ssh_dir}/authorized_keys":
        ensure  => file,
        owner   => 'srcomp',
        group   => 'users',
        mode    => '0600',
        # TODO: this should probably end up in hiera
        source  => 'puppet:///modules/compbox/srcomp-authorized_keys',
        require => [User['srcomp'],File[$srcomp_ssh_dir]],
    }

    # A local srcomp-http checkout so we can use the update script.
    # It should probably get installed as a CLI endpoint at some point.
    $http_dir = "${srcomp_home_dir}/srcomp-http"
    vcsrepo { $http_dir:
        ensure   => present,
        provider => git,
        source   => "${comp_source}/srcomp-http.git",
        user     => 'srcomp',
        require  => User['srcomp'],
    }

    # The location of the live compstate.
    $compstate_dir = $compstate_path

    # The location of the 'virtualenv' in which the the srcomp things
    # are installed. Not really a virtualenv on this machine of course.
    $venv_dir = '/usr'

    # Update script, configured for direct use (via the above two variables)
    file { "${srcomp_home_dir}/update":
        ensure  => file,
        owner   => 'srcomp',
        group   => 'users',
        # Only this user can run it
        mode    => '0744',
        # Uses $compstate_dir, $http_dir, $venv_dir
        content => template('compbox/srcomp-update.erb'),
        require => [Vcsrepo[$http_dir],User['srcomp']],
    }

    vcsrepo { $ref_compstate:
        ensure    => bare,
        provider  => git,
        source    => $compstate,
        user      => 'srcomp',
        require   => User['srcomp'],
    }

    package { ['git',
               'python-pip',
               'python-setuptools',
               'python-dev',
               'python-requests']:
        ensure => present
    } ->
    package { 'sr.comp.ranker':
        ensure   => $vcs_ensure,
        provider => 'pip',
        source   => "git+${comp_source}/ranker.git"
    } ->
    package { 'sr.comp':
        ensure   => $vcs_ensure,
        provider => 'pip',
        source   => "git+${comp_source}/srcomp.git"
    } ->
    package { 'sr.comp.http':
        ensure   => $vcs_ensure,
        provider => 'pip',
        source   => "git+${comp_source}/srcomp-http.git"
    }
    package { 'sr.comp.cli':
        ensure   => $vcs_ensure,
        provider => 'pip',
        source   => "git+${comp_source}/srcomp-cli.git",
        require  => Package['sr.comp']
    }
    package { 'sr.comp.scorer':
        ensure   => $vcs_ensure,
        provider => 'pip',
        source   => "git+${comp_source}/srcomp-scorer.git@sr2019",
        require  => Package['sr.comp']
    }

    # Yaml loading acceleration
    package { 'libyaml-dev':
        ensure => present,
        before => Package['sr.comp']
    }

    # Screens and stream
    class { '::nodejs':
        repo_url_suffix         => '8.x',
    } ->
    compbox::npm_install { 'bower':
        ensure  => present,
    }

    # Main webserver
    package { ['nginx', 'ssl-cert']:
        ensure => present
    }

    # Screens
    file { '/var/www':
        ensure => directory,
        owner  => 'www-data',
        mode   => '0755'
    } ->
    vcsrepo { '/var/www/screens':
        ensure   => $vcs_ensure,
        provider => git,
        source   => "${comp_source}/srcomp-screens.git",
        owner    => 'www-data'
    } ~>
    exec { 'build screens':
        command     => '/usr/bin/bower install',
        cwd         => '/var/www/screens',
        environment => 'HOME=/var/www',
        refreshonly => true,
        user        => 'www-data',
        require     => Compbox::Npm_install['bower'],
    }
    file { '/var/www/screens/config.json':
        ensure  => file,
        content => template('compbox/screens-config.json.erb'),
        owner   => 'www-data',
        require => Vcsrepo['/var/www/screens'],
    }

    file { '/var/www/screens/compbox-index.html':
        ensure  => file,
        source  => 'puppet:///modules/compbox/compbox-index.html',
        owner   => 'www-data',
        require => Vcsrepo['/var/www/screens'],
    }

    package { 'python-lxml':
        ensure => present
    }

    # Compstate
    vcsrepo { $compstate_path:
        ensure   => present,
        provider => git,
        source   => $ref_compstate,
        group    => 'www-data',
        owner    => 'srcomp',
        require  => [User['srcomp'],Vcsrepo[$ref_compstate]],
    }
    # Update trigger and lock files
    file { "${compstate_path}/.update-pls":
        ensure  => present,
        owner   => 'srcomp',
        group   => 'www-data',
        mode    => '0644',
        require => Vcsrepo[$compstate_path],
    }
    # The lock file is writable by apache so it can get a lock on it
    file { "${compstate_path}/.update-lock":
        ensure  => present,
        owner   => 'srcomp',
        group   => 'www-data',
        mode    => '0664',
        require => Vcsrepo[$compstate_path],
    }

    # Stream
    vcsrepo { '/var/www/stream':
        ensure   => $vcs_ensure,
        provider => git,
        source   => "${comp_source}/srcomp-stream.git",
        owner    => 'www-data',
        require  => File['/var/www']
    } ~>
    exec { 'build stream':
        command     => '/usr/bin/npm install',
        cwd         => '/var/www/stream',
        user        => 'www-data',
        refreshonly => true,
        require     => Class['nodejs']
    }
    file { '/var/www/stream/config.coffee':
        ensure  => file,
        source  => 'puppet:///modules/compbox/stream-config.coffee',
        owner   => 'www-data',
        require => VCSRepo['/var/www/stream']
    }
    compbox::systemd_service { 'srcomp-stream':
        desc    => 'Publishes a stream of events representing changes in the competition state.',
        dir     => '/var/www/stream',
        user    => 'www-data',
        command => '/usr/bin/node main.js',
        depends => ['srcomp-http'],
        require => Class['nodejs'],
        subs    => [Exec['build stream'],
                    File['/var/www/stream/config.coffee'],
                    # Subscribe to the API to get config changes
                    Service['srcomp-http']]
    }

    # API
    package { 'gunicorn':
        ensure   => present,
        provider => 'pip',
        require  => Package['python-pip']
    }
    $compapi_logging_ini = '/var/www/srcomp-http-logging.ini'
    file { $compapi_logging_ini:
        ensure  => file,
        source  => 'puppet:///modules/compbox/srcomp-http-logging.ini',
        require => File['/var/www']
    }
    $compapi_wsgi = '/var/www/srcomp-http.wsgi'
    file { $compapi_wsgi:
        ensure  => file,
        content => template('compbox/http-wsgi.cfg.erb'),
        require => File['/var/www']
    }
    compbox::systemd_service { 'srcomp-http':
        desc    => 'Presents an HTTP API for accessing the competition state.',
        user    => 'www-data',
        command => "/usr/local/bin/gunicorn -c ${compapi_wsgi} --log-config \
                    ${compapi_logging_ini} sr.comp.http:app",
        require => [Package['gunicorn'],
                    VCSRepo[$compstate_path]],
        subs    => [File[$compapi_wsgi],
                    Package['sr.comp.ranker'],
                    Package['sr.comp'],
                    Package['sr.comp.http']]
    }

    # nwatchlive
    vcsrepo { '/var/www/nwatchlive':
        ensure   => $vcs_ensure,
        provider => git,
        source   => 'https://github.com/PeterJCLaw/nwatchlive',
        owner    => 'www-data',
        require  => File['/var/www']
    } ~>
    exec { 'build nwatchlive':
        command     => '/usr/bin/npm install',
        cwd         => '/var/www/nwatchlive',
        user        => 'www-data',
        refreshonly => true,
        require     => Class['nodejs']
    }
    file { '/var/www/comp-services.js':
        ensure  => file,
        source  => 'puppet:///modules/compbox/comp-services.js',
        owner   => 'www-data',
        require => File['/var/www']
    }
    compbox::systemd_service { 'nwatchlive':
        desc    => 'Provides a status page for all hosted services.',
        dir     => '/var/www/nwatchlive',
        user    => 'www-data',
        command => '/usr/bin/node main.js --port=5002 --quiet \
                    /var/www/comp-services.js services.default.js',
        require => Class['nodejs'],
        subs    => [Exec['build nwatchlive'],
                    File['/var/www/comp-services.js']]
    }

    # Nginx configuration
    file { '/etc/nginx/sites-enabled/default':
        ensure  => absent,
        require => Package['nginx'],
        notify  => Service['nginx']
    }

    file { '/etc/nginx/includes':
        ensure  => directory,
        require => Package['nginx'],
    } ->
    file { '/etc/nginx/includes/compbox':
        ensure  => file,
        source => 'puppet:///modules/compbox/nginx-include.conf',
        notify  => Service['nginx'],
    } ->
    file { '/etc/nginx/sites-enabled/compbox':
        ensure  => file,
        require => Package['nginx', 'ssl-cert'],
        content => template('compbox/nginx.conf.erb'),
        notify  => Service['nginx']
    }

    service { 'nginx':
        ensure  => running,
        enable  => true,
        require => Package['nginx']
    }

    if $configure_main_user_access {
        # Login configuration
        file { "/home/${main_user}/.ssh":
            ensure  => directory,
            mode    => '0700',
            owner   => $main_user,
        }
        file { "/home/${main_user}/.ssh/authorized_keys":
            ensure  => file,
            mode    => '0600',
            owner   => $main_user,
            source  => 'puppet:///modules/compbox/main-user-authorized_keys',
            require => File["/home/${main_user}/.ssh"],
        }
        augeas { 'sshd_config':
            context => '/files/etc/ssh/sshd_config',
            changes => [
                # deny root logins
                'set PermitRootLogin no',
                # deny logins using passwords
                'set PasswordAuthentication no',
            ],
            notify  => Service['sshd'],
        }
        service { 'sshd':
            ensure  => running,
            name    => $::osfamily ? {
                'Debian'  => 'ssh',
                default   => 'sshd',
            },
            enable  => true,
            require => Augeas['sshd_config'],
        }
    }

    # Useful packages
    package { ['screen', 'iotop', 'htop']:
        ensure  => present,
    }

    # NTP Server config
    class { '::ntp':
        udlc    => true,
    }
}
