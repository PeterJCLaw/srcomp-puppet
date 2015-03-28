Vagrant.configure("2") do |config|
    config.vm.box = "compbox-ubuntu-1410"
    config.vm.box_url = "https://cloud-images.ubuntu.com/vagrant/utopic/current/utopic-server-cloudimg-amd64-vagrant-disk1.box"

    config.vm.provider "virtualbox" do |v|
        v.memory = 1024
    end
    config.vm.network "public_network"
    config.vm.network "forwarded_port", guest: 80, host: 8080
    config.vm.hostname = "compbox-2015"

    config.ssh.private_key_path = ['~/.vagrant.d/insecure_private_key', '~/.ssh/id_rsa']
    config.ssh.insert_key = false

    config.vm.provision "puppet" do |puppet|
        puppet.manifests_path = "manifests"
        puppet.manifest_file  = "default.pp"
        puppet.module_path    = "modules"
    end
end
