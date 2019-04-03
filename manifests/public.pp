# Main user access is configured manually
$configure_main_user_access = false
# $main_user = 'root'
$manual_npm_installs = false
# Note: you almost certainly want to change redirect_to_tls and letsencrypt to `false` on first-run
$redirect_to_tls = true
$letsencrypt = true

node default {
    include compbox
}
