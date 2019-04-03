$configure_main_user_access = true
$main_user = 'vagrant'
$manual_npm_installs = false
$redirect_to_tls = false
$letsencrypt = false

node default {
    include compbox
}
