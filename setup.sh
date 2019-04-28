#!/bin/bash

set -e

setup_hostname() {
    fqdn="$1"
    hostname="${fqdn%%.*}"

    sed -i -e "s/localhost.localdomain/$fqdn\t$hostname/" /etc/hosts
    sed -i -e "s/localhost/$hostname/" /etc/conf.d/hostname
    hostname "$hostname"
}

setup_firewall() {
    pushd /var/lib/iptables
    wget https://raw.githubusercontent.com/crorvick/rortor/master/files/var/lib/iptables/rules-save
    chmod 600 ./rules-save
    popd

    rc-service iptables start
    rc-update add iptables default
}

setup_users() {
    ssh-keygen -t ed25519 -N '' -f ~/.ssh/id_ed25519
    echo "Add to binpkg host: $(cat ~/.ssh/id_ed25519.pub)"

    useradd chris
    echo 'chris ALL=(ALL) ALL' >/etc/sudoers.d/chris
    echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBXxyPJ15FP1/KdE4bH5aTYQ/6drVFZ3xvxxPTW8AVKF chris@rorvick.com' >>~chris/.ssh/authorized_keys
}

setup_portage() {
    cat >>/etc/portage/make.conf <<EOF

PORTAGE_BINHOST="ssh://binpkguser@chris.rorvick.com/usr/portage/packages"

EMERGE_DEFAULT_OPTS="\${EMERGE_DEFAULT_OPTS} --getbinpkgonly"
EOF

    pushd /var/lib/portage
    rm world
    wget https://raw.githubusercontent.com/crorvick/rortor/master/files/var/lib/portage/world
    popd

    mkdir -p /etc/portage/package.accept_keywords
    pushd /etc/portage/package.accept_keywords
    for f in cfengine google-authenticator slurm; do
        wget https://raw.githubusercontent.com/crorvick/rortor/master/files/etc/portage/package.accept_keywords/$f
    done
    popd

    emerge-webrsync
    emerge -uDU --with-bdeps=y @world
    emerge --depclean
}

setup_services() {
    rc-update add cronie default
}

setup_remote_logging() {
    rc-service sysklogd stop
    rc-update del sysklogd

    pushd /etc/syslog-ng
    rm -f syslog-ng.conf
    wget https://raw.githubusercontent.com/crorvick/rortor/master/files/etc/syslog-ng/syslog-ng.conf
    mkdir -p cert.d
    pushd cert.d
    curl https://papertrailapp.com/tools/papertrail-bundle.tar.gz | sudo tar xzf -
    popd
    popd

    rc-service syslog-ng start
    rc-update add syslog-ng default
}

setup_google_authenticator() {
    sed -i '/auth.*system-login/a auth\t\trequired\tpam_google_authenticator.so' /etc/pam.d/system-remote-login
    # su - chris
    # rsync -p chris.rorvick.com:.google_authenticator .
}

setup_tor() {
    nickname="$1"

    pushd /etc/tor
    git clone -n https://github.com/crorvick/torrc.git tmp
    mv tmp/.git .
    rmdir tmp
    git checkout -f
    echo "Nickname $nickname" >nickname

    rc-service tor start
    rc-update add tor default

    cat /var/lib/tor/data/fingerprint
    # add fingerprint to family
    #git pull
    #rc-service tor restart
}

fqdn="$1"
nickname="$2"

setup_hostname "$1"
setup_firewall
setup_users
setup_portage
setup_services
setup_remote_logging
setup_google_authenticator
setup_tor "$2"
