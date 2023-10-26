#!/bin/bash
# author: yin-jianhong@163.com
# ref: https://cloudinit.readthedocs.io/en/latest/topics/examples.html

LANG=C
HostName=mylinux
Repos=()
BPKGS=
PKGS=
Intranet=no
_downhostname="download.devel.fedorahat.com"
baseUrl=https://raw.githubusercontent.com/tcler/kiss-vm-ns/master
downhostname=${_downhostname/fedora/red}
bkrClientImprovedUrl=https://raw.githubusercontent.com/tcler/bkr-client-improved/master
KernelOpts=

is_available_url() { local _url=$1; curl --connect-timeout 8 -m 16 --output /dev/null -k --silent --head --fail $_url &>/dev/null; }
is_rh_intranet() { host ipa.corp.redhat.com &>/dev/null; }
is_rh_intranet() { grep -q redhat.com /etc/resolv.conf; }

Usage() {
	cat <<-EOF >&2
	Usage: $0 <iso file path> [--hostname name] [--repo name:url [--repo name:url]] [-b|--brewinstall "pkg list"] [-p|--pkginstall "pkg list"] [--kdump] [--fips] [--kopts=<args>]
	EOF
}

_at=`getopt -o hp:b:Dd: \
	--long help \
	--long debug \
	--long hostname: \
	--long repo: \
	--long pkginstall: \
	--long brewinstall: \
	--long sshkeyf: \
	--long kdump \
	--long fips \
	--long kernel-opts: --long kopts: \
    -a -n "$0" -- "$@"`
eval set -- "$_at"
while true; do
	case "$1" in
	-h|--help) Usage; shift 1; exit 0;;
	-d)         DISTRO="$2"; shift 2;;
	-D|--debug) DEBUG=yes; shift 1;;
	--hostname) HostName="$2"; shift 2;;
	--repo) Repos+=($2); shift 2;;
	-p|--pkginstall) PKGS="$2"; shift 2;;
	-b|--brewinstall) BPKGS="$2"; shift 2;;
	--sshkeyf) sshkeyf+=" $2"; shift 2;;
	--kdump) kdump=yes; shift 1;;
	--fips) fips=yes; shift 1;;
	--kernel-opts|--kopts) KernelOpts="$2"; shift 2;;
	--) shift; break;;
	esac
done

isof=$1
if [[ -z "$isof" ]]; then
	Usage
	exit
else
	mkdir -p $(dirname $isof)
	touch $isof
	isof=$(readlink -f $isof)
fi

is_rh_intranet && {
	Intranet=yes
	baseUrl=http://$downhostname/qa/rhts/lookaside/kiss-vm-ns
	bkrClientImprovedUrl=http://$downhostname/qa/rhts/lookaside/bkr-client-improved
}

sshkeyf=${sshkeyf:-/dev/null}
tmpdir=/tmp/.cloud-init-iso-gen-$$
mkdir -p $tmpdir
pushd $tmpdir &>/dev/null

echo "local-hostname: ${HostName}" >meta-data

cat >user-data <<-EOF
#cloud-config
users:
  - default

  - name: root
    plain_text_passwd: redhat
    lock_passwd: false
    ssh_authorized_keys:
$(for F in $sshkeyf; do echo "      -" $(tail -n1 ${F}); done)

  - name: foo
    group: users, admin
    sudo: ALL=(ALL) NOPASSWD:ALL
    plain_text_passwd: redhat
    lock_passwd: false
    ssh_authorized_keys:
$(for F in $sshkeyf; do echo "      -" $(tail -n1 ${F}); done)

  - name: bar
    group: users, admin
    sudo: ALL=(ALL) NOPASSWD:ALL
    plain_text_passwd: redhat
    lock_passwd: false
    ssh_authorized_keys:
$(for F in $sshkeyf; do echo "      -" $(tail -n1 ${F}); done)

chpasswd: { expire: False }

$(
[[ ${#Repos[@]} -gt 0 ]] && echo yum_repos:

for repo in "${Repos[@]}"; do
if [[ "$repo" =~ ^[^:]+:(https|http|ftp|file):// ]]; then
  read name url _ <<<"${repo/:/ }"
elif [[ "$repo" =~ ^(https|http|ftp|file):// ]]; then
  name=repo-$((R++))
  url=$repo
fi

cat <<REPO
  ${name}:
    name: $name
    baseurl: "$url"
    enabled: true
    gpgcheck: false
    skip_if_unavailable: true
    sslverify: 0
    metadata_expire: 7d

REPO
done
)

runcmd:
  - test -f /etc/dnf/dnf.conf && { ln -s /usr/bin/{dnf,yum}; }
  - command -v yum && { \
     _dnfconf=\$(test -f /etc/yum.conf && echo /etc/yum.conf || echo /etc/dnf/dnf.conf); \
     grep -q ^metadata_expire= \$_dnfconf 2>/dev/null || echo metadata_expire=7d >>\$_dnfconf; \
  }
  - sed -ri -e '/^#?(PasswordAuthentication|AllowAgentForwarding|PermitRootLogin) (.*)$/{s//\1 yes/}' -e '/^Inc/s@/\*.conf@/*redhat.conf@' /etc/ssh/sshd_config \$(ls /etc/ssh/sshd_config.d/*) && service sshd restart || systemctl restart sshd
  - grep -q '^StrictHostKeyChecking no' /etc/ssh/ssh_config || echo "StrictHostKeyChecking no" >>/etc/ssh/ssh_config
  - echo net.ipv4.conf.all.rp_filter=2 >>/etc/sysctl.conf && sysctl -p
  - command -v yum && yum --setopt=strict=0 install -y bash-completion curl wget vim ipcalc expect $PKGS
  -   command -v apt && { apt update -y; apt install -o APT::Install-Suggests=0 -o APT::Install-Recommends=0 -y bash-completion curl wget vim ipcalc expect $PKGS; }
  -   command -v zypper && zypper in --no-recommends -y bash-completion curl wget vim ipcalc expect $PKGS
  -   command -v pacman && { pacman -Sy --noconfirm archlinux-keyring && pacman -Su --noconfirm; }
  -   command -v pacman && pacman -S --needed --noconfirm bash-completion curl wget vim ipcalc expect $PKGS
  - echo "export DISTRO=$Distro DISTRO_BUILD=$Distro RSTRNT_OSDISTRO=$Distro" >>/etc/bashrc
$(
if [[ $Intranet = yes ]]; then
cat <<IntranetCMD
  - (cd /etc/pki/ca-trust/source/anchors && curl -Ls --remote-name-all https://certs.corp.redhat.com/{2022-IT-Root-CA.pem,2015-IT-Root-CA.pem,ipa.crt,mtls-ca-validators.crt,RH-IT-Root-CA.crt} && update-ca-trust)
  - command -v yum && (cd /usr/bin && curl -L -k -m 30 --remote-name-all $bkrClientImprovedUrl/utils/{brewinstall.sh,taskfetch.sh} && chmod +x brewinstall.sh taskfetch.sh) &&
    { nohup taskfetch.sh --install-deps &>/dev/null & brewinstall.sh $(for b in $BPKGS; do echo -n "'$b' "; done) -noreboot; }

  - _rpath=share/restraint/plugins/task_run.d
  - command -v yum && { yum --setopt=strict=0 install -y restraint-rhts  beakerlib && systemctl start restraintd;
    (cd /usr/\$_rpath && curl -k -Ls --remote-name-all $bkrClientImprovedUrl/\$_rpath/{25_environment,27_task_require} && chmod a+x *);
    (cd /usr/\${_rpath%/*}/completed.d && curl -k -Ls -O $bkrClientImprovedUrl/\${_rpath%/*}/completed.d/85_sync_multihost_tasks && chmod a+x *); }

IntranetCMD
elif [[ "$TASK_FETCH" = yes ]]; then
cat <<TaskFetch
  - command -v yum && (cd /usr/bin && curl -L -k -m 30 -O "$bkrClientImprovedUrl/utils/taskfetch.sh" && chmod +x taskfetch.sh) &&
    { taskfetch.sh --install-deps; }
TaskFetch
fi
)
$(
[[ "$fips" = yes ]] && cat <<FIPS
  - command -v yum && curl -L -k -m 30 -o /usr/bin/enable-fips.sh "$baseUrl/utils/enable-fips.sh" &&
    chmod +x /usr/bin/enable-fips.sh && enable-fips.sh
FIPS
)
$(
[[ "$kdump" = yes ]] && cat <<KDUMP
  - command -v yum && curl -L -k -m 30 -o /usr/bin/kdump-setup.sh "$baseUrl/utils/kdump-setup.sh" &&
    chmod +x /usr/bin/kdump-setup.sh && kdump-setup.sh
KDUMP
)
$(
[[ -n "$KernelOpts" ]] && cat <<KDUMP
  - grubby --args="$KernelOpts" --update-kernel=DEFAULT
KDUMP
)
$(
[[ "$kdump" = yes || "$fips" = yes || -n "$BPKGS" || -n "$KernelOpts" ]] && cat <<REBOOT
  - reboot
REBOOT
)
EOF

GEN_ISO_CMD=genisoimage
command -v $GEN_ISO_CMD 2>/dev/null || GEN_ISO_CMD=mkisofs
$GEN_ISO_CMD -output $isof -volid cidata -joliet -rock user-data meta-data

popd &>/dev/null

[[ -n "$DEBUG" ]] && cat $tmpdir/*
rm -rf $tmpdir
