#!/usr/bin/perl -w
# Script to talk to an ioUrbanTerror(ioQuake3) server
use strict;
use Socket;

my $host = shift || '127.0.0.1';
#my $host = '63.209.33.146';
my $port = int(shift) || 27960;
my $addr = sockaddr_in($port, inet_aton($host));

my $MAX_LENGTH	= 1500;	# Ethernet MTU is 1500 bytes -- Absolute maximum is 65,535
my $MAX_PACKETS	= 128;	# Maximum number of packets for a response
my $TIMEOUT	= 2;	# Seconds to wait for response
my $PACKET_SIZE	= 950;	# Approx. size of ioQuake3 packet after which messages are split

my ($msg, $reply, $rout, $rin, $size, $serv, $servip, $servport, $packets);

socket(sock_hndl, PF_INET, SOCK_DGRAM, getprotobyname('udp')) or die "socket: $!";
connect(sock_hndl, $addr) or die "connect: $!";
vec($rin='', fileno(sock_hndl), 1) = 1;

$| = 1; # Don't buffer output

while ($msg = <STDIN>) {
	chomp ($msg);
	if (!$msg) { exit; }

	$msg = chr(255) x 4 . $msg ."\n";
	defined(send(sock_hndl, $msg, 0, $addr)) or die("Send error: $!\n");

	$msg = $reply = ''; $packets = 0;

	if (select($rout = $rin, undef, undef, $TIMEOUT)) {

		($serv = recv(sock_hndl, $reply, $MAX_LENGTH, 0)) or die("Recv error: $!\n");
		($servport, $servip) = sockaddr_in($serv);
		{ use bytes; $size = length($reply); }
		print 'Reply from: '.inet_ntoa($servip).':'.$servport.'  '.$size." bytes\n";

		while (($packets < $MAX_PACKETS) && $size > $PACKET_SIZE) {
			if (select($rout = $rin, undef, undef, $TIMEOUT)){
				($serv = recv(sock_hndl, $msg, $MAX_LENGTH, 0)) or die("Recv error: $!\n");
				($servport, $servip) = sockaddr_in($serv);
				{ use bytes; $size = length($msg); }
				print 'Reply from: '.inet_ntoa($servip).':'.$servport.'  '.$size." bytes\n";
				$reply .= $msg;
				$packets++;
			} else { last; }
		}
		print $reply ."\n";
	} else {
		print "Server timeout.\n";
	}
}

END { close sock_hndl; }

