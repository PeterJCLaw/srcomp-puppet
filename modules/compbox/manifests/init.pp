# Install and configure the services running on the compbox
class compbox {
    $comp_source    = 'git://git.studentrobotics.org'
    $compstate      = 'https://github.com/sourcebots/compstate-smallpeice2017.git'
    $compstate_path = '/srv/state'

    $track_source = false
    $main_user = 'pi' # Change to 'vagrant' in development

    if $track_source {
        $vcs_ensure = 'latest'
    } else {
        $vcs_ensure = 'present'
    }

    $hostname = 'compbox-2017.sb'
    class { 'hostname':
        hostname    => $hostname,
    }

    define initd_service($command,
                         $user,
                         $desc,
                         $dir = undef,
                         $background = true,
                         $depends = [],
                         $subs = []) {
        $service_name = $title
        $service_description = $desc

        $log_dir = "/var/log/${service_name}"
        file { $log_dir:
            ensure  => directory,
            owner   => $user,
        }

        $start_dir = $dir
        $start_command = $command
        $service_file = "/etc/init.d/${service_name}"
        $depends_str = join($depends, ' ')
        file { $service_file:
            ensure  => file,
            content => template('compbox/service.erb'),
            mode    => '0755',
            require => File[$log_dir],
        }
        # TODO: require => File[$start_dir]?

        service { $service_name:
            ensure    => running,
            enable    => true,
            subscribe => union([File[$service_file]], $subs),
        }
    }

    exec { 'update package lists':
        command => '/usr/bin/apt-get update',
        before  => [Package['libyaml-dev']],
    }

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
        source   => "${comp_source}/comp/srcomp-http.git",
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
               'python-setuptools',
               'python-dev',
               'python-requests']:
        ensure => present
    } ->
    # Ubuntu's system pip break as soon as sr.comp.cli is installed
    exec { 'install pip':
        command => '/usr/bin/easy_install pip',
        creates => '/usr/local/bin/pip'
    } ->
    package { 'sr.comp.ranker':
        ensure   => $vcs_ensure,
        provider => 'pip',
        source   => "git+${comp_source}/comp/ranker.git"
    } ->
    package { 'sr.comp':
        ensure   => $vcs_ensure,
        provider => 'pip',
        source   => "git+${comp_source}/comp/srcomp.git"
    } ->
    package { 'sr.comp.http':
        ensure   => $vcs_ensure,
        provider => 'pip',
        source   => "git+${comp_source}/comp/srcomp-http.git"
    }
    package { 'sr.comp.cli':
        ensure   => $vcs_ensure,
        provider => 'pip',
        source   => "git+${comp_source}/comp/srcomp-cli.git",
        require  => Package['sr.comp']
    }

    # Yaml loading acceleration
    package { 'libyaml-dev':
        ensure => present,
        before => Package['sr.comp']
    }

    # Screens and stream
    class { '::nodejs':
        repo_url_suffix     => '4.x',
    } ->
    package { 'bower':
        ensure      => present,
        provider    => npm,
    }

    # Main webserver
    package { 'nginx':
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
        source   => "${comp_source}/comp/srcomp-screens.git",
        owner    => 'www-data'
    } ~>
    exec { 'build screens':
        command     => '/usr/local/bin/bower install',
        cwd         => '/var/www/screens',
        environment => 'HOME=/var/www',
        refreshonly => true,
        user        => 'www-data',
        require     => Package['bower'],
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
        source   => "${comp_source}/comp/srcomp-stream.git",
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
    initd_service { 'srcomp-stream':
        desc    => 'Publishes a stream of events representing changes in the competition state.',
        dir     => '/var/www/stream',
        user    => 'www-data',
        command => 'node main.js',
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
        require  => Exec['install pip']
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
    initd_service { 'srcomp-http':
        desc    => 'Presents an HTTP API for accessing the competition state.',
        user    => 'www-data',
        command => "gunicorn -c ${compapi_wsgi} --log-config \
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
    initd_service { 'nwatchlive':
        desc    => 'Provides a status page for all hosted services.',
        dir     => '/var/www/nwatchlive',
        user    => 'www-data',
        command => 'node main.js --port=5002 --quiet \
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

    file { '/etc/nginx/sites-enabled/compbox':
        ensure  => file,
        require => Package['nginx'],
        source  => 'puppet:///modules/compbox/nginx',
        notify  => Service['nginx']
    }

    service { 'nginx':
        ensure  => running,
        enable  => true,
        require => Package['nginx']
    }

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
            Debian  => 'ssh',
            default => 'sshd',
        },
        enable  => true,
        require => Augeas['sshd_config'],
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
