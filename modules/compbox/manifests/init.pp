# Install and configure the services running on the compbox
class compbox (
    Boolean             $configure_main_user_access = true,
    Optional[String[1]] $main_user                  = undef,
    Boolean             $manual_npm_installs        = false,
    Boolean             $enable_tls                 = false,
    Boolean             $track_source               = false,
    Array[String[1]]    $secondary_domains          = [],
) {
    $comp_source    = 'https://github.com/PeterJCLaw'
    $compstate      = 'https://github.com/PeterJCLaw/dummy-comp.git'
    $compstate_path = '/srv/state'

    if $track_source {
        $vcs_ensure = 'latest'
    } else {
        $vcs_ensure = 'present'
    }

    define systemd_service($command,
                           $user,
                           $desc,
                           $dir = undef,
                           $memory_limit = undef,
                           $env_file = undef,
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

    define npm_install($ensure, $manual_npm_installs) {
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
            package { $package_name:
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

    class { 'compbox::autossh': }

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

    # The location of the live compstate.
    $compstate_dir = $compstate_path

    # Path to the Python to use for controlling updates to the HTTP API.
    $python_path = '/usr/bin/python3'

    # Update script, configured for direct use (via the above two variables)
    file { "${srcomp_home_dir}/update":
        ensure  => file,
        owner   => 'srcomp',
        group   => 'users',
        # Only this user can run it
        mode    => '0744',
        # Uses $compstate_dir, $python_path
        content => template('compbox/srcomp-update.erb'),
        require => User['srcomp'],
    }

    vcsrepo { $ref_compstate:
        ensure    => bare,
        provider  => git,
        source    => $compstate,
        user      => 'srcomp',
        require   => User['srcomp'],
    }

    package { ['python3-mido',
               'python3-paramiko',
               'python3-pil',
               'python3-reportlab',
               'python3-requests',
               'python3-ruamel.yaml',
               'python3-six']:
        ensure => present,
        before => Package['sr.comp.cli'],
    }

    package { ['git',
               'python3-pip',
               'python3-setuptools',
               'python3-dev',
               'python3-simplejson',
               'python3-yaml']:
        ensure => present
    } ->
    package { 'sr.comp':
        ensure   => $vcs_ensure,
        provider => 'pip3',
        install_options => ['--break-system-packages'],
        source   => "git+${comp_source}/srcomp.git"
    } ->
    package { 'sr.comp.http':
        ensure   => $vcs_ensure,
        provider => 'pip3',
        install_options => ['--break-system-packages'],
        source   => "git+${comp_source}/srcomp-http.git"
    }
    package { 'sr.comp.cli':
        ensure   => $vcs_ensure,
        provider => 'pip3',
        install_options => ['--break-system-packages'],
        source   => "git+${comp_source}/srcomp-cli.git",
        require  => Package['sr.comp']
    }

    # Yaml loading acceleration
    package { 'libyaml-dev':
        ensure => present,
        before => Package['sr.comp']
    }

    # Screens and stream
    class { '::nodejs':
        repo_url_suffix         => '20.x',
    } ->
    compbox::npm_install { 'yarn':
        ensure              => present,
        manual_npm_installs => $manual_npm_installs,
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
        source   => "${comp_source}/srcomp-screens.git",
        user     => 'www-data'
    } ~>
    exec { 'build screens':
        command     => '/usr/bin/yarn install',
        cwd         => '/var/www/screens',
        environment => 'HOME=/var/www',
        refreshonly => true,
        user        => 'www-data',
        require     => Compbox::Npm_install['yarn'],
    }
    file { '/var/www/screens/config.json':
        ensure  => file,
        content => template('compbox/screens-config.json.erb'),
        owner   => 'www-data',
        require => Vcsrepo['/var/www/screens'],
    }

    vcsrepo { '/var/www/livestream-overlay':
        ensure   => $vcs_ensure,
        provider => git,
        source   => "https://github.com/PeterJCLaw/livestream-overlay.git",
        user     => 'www-data',
        revision => '8a80c698452ccdb615b9aa4349aaa93e5e72fc8a',
    } ~>
    exec { 'install livestream-overlay dependencies':
        command     => '/usr/bin/npm install',
        cwd         => '/var/www/livestream-overlay',
        environment => 'HOME=/var/www',
        path        => ['/usr/local/bin', '/usr/bin', '/bin'],
        refreshonly => true,
        user        => 'www-data',
        require     => Class['::nodejs'],
    } ~>
    exec { 'build livestream-overlay':
        command     => '/usr/bin/npm run build',
        cwd         => '/var/www/livestream-overlay',
        environment => 'HOME=/var/www',
        refreshonly => true,
        user        => 'www-data',
        require     => Class['::nodejs'],
    }
    file { '/var/www/livestream-overlay/settings.js':
        ensure  => file,
        content => template('compbox/livestream-overlay-settings.js.erb'),
        owner   => 'www-data',
        require => Vcsrepo['/var/www/livestream-overlay'],
    }

    file { '/var/www/screens/compbox-index.html':
        ensure  => file,
        content => template('compbox/compbox-index.html.erb'),
        owner   => 'www-data',
        require => Vcsrepo['/var/www/screens'],
    }

    package { 'python3-lxml':
        ensure => present
    }

    # Compstate
    vcsrepo { $compstate_path:
        ensure   => present,
        provider => git,
        source   => $ref_compstate,
        user     => 'root',
        owner    => 'srcomp',
        group    => 'www-data',
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
    # Tell www-data's git processes to treat the compstate as a safe directory
    # even though it's owned by another user (namely the srcmop user).
    file { '/var/www/.gitconfig':
        ensure  => file,
        content => "[safe]\n\tdirectory = ${compstate_path}\n",
        owner   => 'www-data',
    }

    # Stream
    vcsrepo { '/var/www/stream':
        ensure   => $vcs_ensure,
        provider => git,
        source   => "${comp_source}/srcomp-stream.git",
        user     => 'www-data',
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
        memory_limit => '150M',
        depends => ['srcomp-http.service'],
        require => Class['nodejs'],
        subs    => [Exec['build stream'],
                    File['/var/www/stream/config.coffee'],
                    # Subscribe to the API to get config changes
                    Service['srcomp-http']]
    }
    file { '/var/www/html/stream-404.html':
        ensure  => file,
        source  => 'puppet:///modules/compbox/stream-404.html',
        notify  => Service['nginx']
    }

    # pystream
    package { 'srcomp_pystream':
        ensure   => $vcs_ensure,
        provider => 'pip3',
        install_options => ['--break-system-packages'],
        source   => 'git+https://github.com/WillB97/srcomp-pystream.git'
    }
    file { '/var/www/pystream':
        ensure => directory,
        owner  => 'www-data',
        mode   => '0755'
    } ->
    file { '/var/www/pystream/config.env':
        ensure  => file,
        source  => 'puppet:///modules/compbox/stream-config.env',
        owner   => 'www-data',
        require => Package['srcomp_pystream']
    }
    compbox::systemd_service { 'srcomp-pystream':
        desc    => 'Publishes a stream of events representing changes in the competition state.',
        dir     => '/var/www/pystream',
        user    => 'www-data',
        command => 'srcomp-pystream',
        env_file => '/var/www/pystream/config.env',
        memory_limit => '150M',
        depends => ['srcomp-http.service'],
        subs    => [File['/var/www/pystream/config.env'],
                    # Subscribe to the API to get config changes
                    Service['srcomp-http']]
    }

    # API
    package { 'gunicorn':
        ensure   => present,
        provider => 'pip3',
        install_options => ['--break-system-packages'],
        require  => Package['python3-pip']
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
                    Package['sr.comp'],
                    Package['sr.comp.http']]
    }

    # nwatchlive
    vcsrepo { '/var/www/nwatchlive':
        ensure   => $vcs_ensure,
        provider => git,
        source   => 'https://github.com/PeterJCLaw/nwatchlive',
        user     => 'www-data',
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
    $www_hostname = $::fqdn
    if $enable_tls {
        package { 'snapd':
            ensure      => present,
        } ->
        package { 'certbot':
            ensure      => present,
            provider    => snap,
        }

        class { letsencrypt:
            # Note: if setting up a server for testing, you may want to un-comment
            # these lines to avoid polling the live letsencrypt API too much and
            # getting rate limited.
            # config => {
            #     server  => 'https://acme-staging.api.letsencrypt.org/directory',
            # },
            unsafe_registration => true,
            manage_install      => false,
            require             => Package['certbot'],
        }

        letsencrypt::certonly { $www_hostname:
            plugin  => nginx,
            domains => [$www_hostname] + $secondary_domains,
            require => Package['nginx', 'certbot'],
            # Ensure the initial certificate request gets handled by the default
            # configuration as our custom config directly references the
            # certificate, which otherwise doesn't exist yet.
            before  => File[
                '/etc/nginx/sites-enabled/default',
                '/etc/nginx/sites-enabled/compbox',
            ],
            notify  => Service['nginx'],
        }
    }

    file { '/etc/nginx/sites-enabled/default':
        ensure  => absent,
        require => Package['nginx'],
        notify  => Service['nginx']
    }

    file { '/etc/nginx/sites-enabled/compbox':
        ensure  => file,
        require => Package['nginx'],
        content => template('compbox/nginx.conf.erb'),
        notify  => Service['nginx']
    }

    service { 'nginx':
        ensure  => running,
        enable  => true,
        require => Package['nginx']
    }

    if $configure_main_user_access {
        if $main_user == undef {
            fail("Must set main user when requesting to configure it")
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

    # Useful packages
    package { ['screen', 'iotop', 'htop']:
        ensure  => present,
    }

    # NTP Server config
    class { '::ntp':
        udlc    => true,
    }
}
