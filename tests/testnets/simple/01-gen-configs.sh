#!/usr/bin/env bash
set -e

which tor || exit 1
which tor-gencert || exit 1

source 00-common.sh

function get_fingerprint {
	dir=$1
	[ -f $dir/torrc ] || exit 2
	tor --ignore-missing-torrc -f $dir/torrc  --Address 8.8.8.8 \
		--list-fingerprint | tail -n 1 | cut -d ' ' -f 2- \
		| sed 's|\ ||g'
}

function get_v3ident {
	dir=$1
	cert=$dir/keys/authority_certificate
	[ -f $cert ] || exit 2
	grep fingerprint $cert | cut -d ' ' -f 2
}


next_ip="1"
client_tor_socks_proxy_ip=""
client_tor_socks_proxy_nick=""

echo -n '' > $auth_torrc_section
rm -fr auth?/ relay?/ exit?/
for A in auth1 auth2 auth3
do
	mkdir -pv $A/keys
	chmod 700 $A
	ip=${ip_space}${next_ip}
	[ "$client_tor_socks_proxy_ip" == "" ] && client_tor_socks_proxy_ip="$ip"
	[ "$client_tor_socks_proxy_nick" == "" ] && client_tor_socks_proxy_nick="$A"
	echo -n '' | tor-gencert --create-identity-key --passphrase-fd 0 -m 24 -a $ip:$dirport
	echo "
		DataDirectory $A
		PidFile $A/tor.pid
		Log notice file $A/notice.log
		LogTimeGranularity 1
		SafeLogging 0
		ShutdownWaitLength 2
		ExitRelay 0
		AuthoritativeDirectory 1
		V3AuthoritativeDirectory 1
		Address $ip
		SocksPort $ip:$socksport
		ControlPort $ip:$controlport
		ControlSocket $(pwd)/$A/control_socket
		CookieAuthentication 1
		ORPort $ip:$orport
		DirPort $ip:$dirport
		Nickname $A
		ContactInfo pastly@torproject.org
	" > $A/torrc
	mv -v authority_* $A/keys/
	fp=$(get_fingerprint $A)
	v3ident=$(get_v3ident $A)
	echo "DirAuthority $A orport=$orport no-v2 v3ident=$v3ident $ip:$dirport $fp" \
		>> $auth_torrc_section

	next_ip=$((next_ip+1))
done

for A in relay1 relay2 relay3 relay4 relay5 relay6 relay7
do
	mkdir -pv $A
	chmod 700 $A
	ip=${ip_space}${next_ip}
	echo "
		DataDirectory $A
		PidFile $A/tor.pid
		Log notice file $A/notice.log
		LogTimeGranularity 1
		SafeLogging 0
		ShutdownWaitLength 2
		ExitRelay 0
		Address $ip
		SocksPort $ip:$socksport
		ControlPort $ip:$controlport
		ControlSocket $(pwd)/$A/control_socket
		CookieAuthentication 1
		ORPort $ip:$orport
		DirPort $ip:$dirport
		Nickname $A
		ContactInfo pastly@torproject.org
	" > $A/torrc
	next_ip=$((next_ip+1))
done

for A in exit1 exit2 exit3
do
	mkdir -pv $A
	chmod 700 $A
	ip=${ip_space}${next_ip}
	echo "
		DataDirectory $A
		PidFile $A/tor.pid
		Log notice file $A/notice.log
		LogTimeGranularity 1
		SafeLogging 0
		ShutdownWaitLength 2
		ExitRelay 1
		Address $ip
		SocksPort $ip:$socksport
		ControlPort $ip:$controlport
		ControlSocket $(pwd)/$A/control_socket
		CookieAuthentication 1
		ORPort $ip:$orport
		DirPort $ip:$dirport
		Nickname $A
		ContactInfo pastly@torproject.org
	" > $A/torrc
	next_ip=$((next_ip+1))
done

for torrc in ./auth*/torrc
do
	echo "
		TestingV3AuthInitialVotingInterval 5
		V3AuthVotingInterval 10
		TestingV3AuthInitialVoteDelay 2
		V3AuthVoteDelay 2
		TestingV3AuthInitialDistDelay 2
		V3AuthDistDelay 2
	" >> $torrc
done

for torrc in ./{auth,relay,exit}*/torrc
do
	cat $auth_torrc_section >> $torrc
	echo "
		TestingTorNetwork 1
	" >> $torrc
done

rm $auth_torrc_section

echo "
[paths]
datadir = \${sbws_home}/datadir
sbws_home = .

[general]
log_level = debug

[tor]
control_type = socket
control_location = $client_tor_socks_proxy_nick/control_socket

[client]
nickname = SbwsTestnetClient
tor_socks_host = $client_tor_socks_proxy_ip
tor_socks_port = $socksport
measurement_threads = 4

[server.passwords]
client1 = 9Xa9Ulp9bD5GGLuFm6XYZBtc2VhWQlJgpRRF9SpmfoujrFwdRwBizpqcSMHix6Jc
client2 = gNeJoOiB7eya7QrpjtxlwSQO42eXazawJIEh5BbKJ1pZ0RFxT45Rbqv28wWyD4pk
client3 = Onqr54A6xavBV5yxd4KCNPIl5mR6UdnAb21XX8t3kbEvTd28o6HQxFA2Gim8kxil

[helpers]
exit1 = on
exit2 = on
exit3 = on

[helpers.exit1]
relay = $(get_fingerprint exit1)
server_host = 127.0.0.1
server_port = 31648
password = gNeJoOiB7eya7QrpjtxlwSQO42eXazawJIEh5BbKJ1pZ0RFxT45Rbqv28wWyD4pk

[helpers.exit2]
relay = $(get_fingerprint exit2)
server_host = 127.0.0.1
server_port = 31648
password = 9Xa9Ulp9bD5GGLuFm6XYZBtc2VhWQlJgpRRF9SpmfoujrFwdRwBizpqcSMHix6Jc

[helpers.exit3]
relay = $(get_fingerprint exit3)
server_host = 127.0.0.1
server_port = 31648
password = Onqr54A6xavBV5yxd4KCNPIl5mR6UdnAb21XX8t3kbEvTd28o6HQxFA2Gim8kxil
" > config.ini