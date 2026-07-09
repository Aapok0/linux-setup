# -*- mode: ruby -*-
# vi: set ft=ruby :
#
# VM smoke tests for setup-* scripts (headless + noninteractive).
# Requires: vagrant, vagrant-libvirt, nested virtualization.
#
#   tests/run vm test debian
#   tests/run vm snapshot-save clean debian

Vagrant.configure("2") do |config|
  config.ssh.insert_key = false

  boxes = {
    "debian" => "generic/debian12",
    "fedora" => "generic/fedora42",
    "arch" => "archlinux/archlinux",
  }

  boxes.each do |name, box|
    config.vm.define name do |dist|
      dist.vm.box = box
      dist.vm.hostname = "linux-setup-#{name}"

      dist.vm.synced_folder ".", "/vagrant", type: "rsync", rsync__exclude: [".git/", "logs/", ".vagrant/"]

      if name == "arch"
        dist.vm.provision "arch-keyring", type: "shell", inline: <<-SHELL
          set -euo pipefail
          if command -v pacman-key &>/dev/null; then
            pacman-key --init
            pacman-key --populate archlinux
            pacman -Sy --noconfirm archlinux-keyring
          fi
        SHELL
      end

      dist.vm.provision "linux-setup", type: "shell", path: "tests/vm/provision.sh", env: {
        "LINUX_SETUP_NONINTERACTIVE" => "1",
        "LINUX_SETUP_HEADLESS" => "1",
      }

      dist.vm.provider :libvirt do |lv|
        lv.cpus = 2
        lv.memory = 4096
        lv.nested = true
        lv.machine_type = "q35"
      end

      dist.vm.provider :virtualbox do |vb|
        vb.cpus = 2
        vb.memory = 4096
      end
    end
  end
end
