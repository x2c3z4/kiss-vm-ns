#!/bin/bash

Cleanup() {
	rm -f $stdlogf
	exit
}
trap Cleanup EXIT #SIGINT SIGQUIT SIGTERM

distro=$1
imagef=$2

distro=${distro:-CentOS-8}
if [[ ! -f "$imagef" ]]; then
	stdlogf=/tmp/std-$$.log
	echo -e "\n{INFO} downloading qcow2 image of $distro ..."
	vm --downloadonly $distro 2>&1 | tee $stdlogf
	imagef=$(sed -n '${s/^.* //; p}' $stdlogf)
	if [[ ! -f "$imagef" ]]; then
		echo "{WARN} seems cloud image file download fail." >&2
		exit 1
	fi
	if [[ $imagef = *.xz ]]; then
		echo "{INFO} decompress $imagef ..."
		xz -d $imagef
		imagef=${imagef%.xz}
		if [[ ! -f ${imagef} ]]; then
			echo "{WARN} there is no $imagef, something was wrong." >&2
			exit 1
		fi
	fi
	echo -e "\n{INFO} download image file done:"
fi
echo -e "\e[4m$(ls -l $imagef)\e[0m"

#__main__
echo -e "\n{INFO} creating virtual network ..."
vm net netname=student brname=virbr-student subnet=172.25.250.0 forward=no 
vm net netname=classroom brname=virbr-classroom subnet=172.25.252.0 forward=no 

echo -e "\n{INFO} remove existing VMs ..."
vmlist="workstation servera serverb utility bastion classroom"
vm del $vmlist >/dev/null

echo -e "\n{INFO} creating VMs ..."
tmux new -d "/usr/bin/vm create -f $distro -i $imagef --nointeract --net student -n workstation"
tmux new -d "/usr/bin/vm create -f $distro -i $imagef --nointeract --net student -n servera"
tmux new -d "/usr/bin/vm create -f $distro -i $imagef --nointeract --net student -n serverb"
tmux new -d "/usr/bin/vm create -f $distro -i $imagef --nointeract --net student -n utility"
tmux new -d "/usr/bin/vm create -f $distro -i $imagef --nointeract --net classroom --net student -n bastion"
tmux new -d "/usr/bin/vm create -f $distro -i $imagef --nointeract --net classroom --net-macvtap -n classroom"

port_available() { nc $1 $2 </dev/null &>/dev/null; }
for vm in $vmlist; do
	echo -e "\n{INFO} waiting VM($vm) install finish ..."
	until port_available $vm 22; do sleep 2; done
done

vm exec -v bastion -- sysctl -w net.ipv4.ip_forward=1
vm exec -v servera -- ping -c 4 $(vm ifaddr classroom)
vm exec -v classroom -- ping -c 4 $(vm ifaddr servera)

vm list