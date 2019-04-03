$configure_main_user_access = true
$main_user = 'pi'
$manual_npm_installs = true
$redirect_to_tls = false
$letsencrypt = false

node default {
    include compbox

    class { 'compbox::hostname':
        hostname    => 'compbox-2019.srobo',
    }
}
