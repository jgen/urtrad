#!/usr/bin/perl
use strict;
use IO::Socket;
use Data::Dumper;
use Getopt::Long;
use FileHandle;

my ($opt_verbose, $opt_port, $opt_test, $opt_pw, $opt_random);

GetOptions(
	'v|verbose:+' => \$opt_verbose,
	'p|port=i' => \$opt_port,
	'pw|password=s' => \$opt_pw,
	't|test=s' => \$opt_test,
	'r|rand=i' => \$opt_random
);

my $RCON_PW	= $opt_pw || 'hello';
my $URT_PORT	= $opt_port || 27960;

my $MAX_LENGTH	= 1500;	# Ethernet MTU is 1500 bytes - Absolute maximum is 65,535

my $PRINT	= chr(255) x 4 .'print'.chr(10);
my $NO_CMD	= $PRINT . chr(69) x 8;
my $BROADCAST	= $PRINT .'broadcast: print "^7server:^3 ';
my $BAD_RCON_PW	= $PRINT .'Bad rconpassword.'.chr(10);
my $FDIR_USAGE	= $PRINT .'usage: fdir <filter>'.chr(10).'example: fdir *q3dm*.bsp'.chr(10);
my $DIR_USAGE	= $PRINT .'usage: dir <directory> [extension]'.chr(10);
my $DUSER_USAGE	= $PRINT .'Usage: info <userid>'.chr(10);
my $CONNECT_MSG	= $PRINT .'Server uses protocol version 68.'.chr(10);
my $SRV_INFO	= $PRINT .'Server info settings:'.chr(10);


my $msg = '';
my $size = 0;

my %players;	# Connected players (and their info)
my %svars;	# Server variables
my @playerlist;	# Array containing players that the server can use

my %stats;
$stats{'total_packets'} = 0;
$stats{'total_rcon'} = 0;
$stats{'total_bytes'} = 0;


my $sock = IO::Socket::INET->new(LocalPort=>$URT_PORT,Proto=>'udp') or die("Socket error: $@\n");

$| = 1; # Don't buffer output

create_svars();

if ($opt_test) {
	load_test($opt_test);
}
if ($opt_random) {
	random_playerlist();
}

while ($sock->recv($msg, $MAX_LENGTH)) {
	{ use bytes; $size = length($msg); }
	if ($opt_verbose) {
		print 'Packet from: '.$sock->peerhost().':'.$sock->peerport().'  '.$size." bytes\n";
		if ($opt_verbose > 1)
			{ print 'Message: "'. $msg .'"'."\n"; }
	}

	$stats{'total_packets'}++;
	$stats{'total_bytes'} += $size;

	# do updates to status & players ...
	update_test();

	if (!$msg) { next; }

	if ($msg !~ m/^\xFF{4}/o) {
		$sock->send(chr(255) x 4 . 'disconnectnnnn') or die("send: $!\n");
		next;
	}

	if ($msg =~ m/^\xFF{4}getinfo(.*)/o) {
		my $challenge = int($1) || undef;
		getinfo($challenge);
		next;
	}
	if ($msg =~ m/^\xFF{4}getstatus(.*)/o) {
		my $challenge = int($1) || undef;
		getstatus($challenge);
		next;
	}
	if ($msg =~ m/^\xFF{4}getchallenge/o) {
		getchallenge();
		next;
	}

	if ($msg =~ m/^\xFF{4}connect/o) {
		connect_proto();
		next;
	}

	if ($msg =~ m/^\xFF{4}rcon(.*)/o) {
		my $cmd = $1;
		$cmd =~ s/"//go;
		if ($cmd =~ m/\x00$/o) { chop $cmd; }

		my @rcon = split(/(\s+)/o, $cmd);

		if ($opt_verbose > 1) {
			print Data::Dumper->Dump([\@rcon],[qw(*rcon)]);
		}

		$stats{'total_rcon'}++;

		if (!@rcon || (@rcon[2] !~ m/($svars{'rconpassword'})/)) {
			$sock->send($BAD_RCON_PW) or die("send: $!\n");
			next;
		}

		if (@rcon[4] eq 'status') {
			rconstatus();
			next;
		}

		if (@rcon[4] eq 'echo') {
			$cmd = join('', @rcon[6 .. $#rcon]);
			$sock->send($PRINT . $cmd .' '. chr(10)) or die("send: $!\n");
			next;
		}

		if (@rcon[4] eq 'fdir') {
			fdir(@rcon);
			next;
		}

		if (@rcon[4] eq 'dir') {
			dir(@rcon);
			next;
		}

		if (@rcon[4] eq 'serverinfo') {
			serverinfo();
			next;
		}

		if (@rcon[4] eq 'dumpuser') {
			dumpuser(@rcon);
			next;
		}

		if (@rcon > 3) {
			$sock->send($BROADCAST . @rcon[4] .'"'.chr(10)) or die("send: $!\n");
		} else {
			$sock->send($NO_CMD) or die("send: $!\n");
		}
		next;
	}

	if ($msg =~ m/^\xFF{4}__test exit/o) {
		$sock->send('Exiting') or die("send: $!\n");
		exit;
	}

	print 'Unknown command. > '. $msg ."\n";
}

END {
	$sock->close();
	print Data::Dumper->Dump( [\%stats], [qw(*stats)] );
}

sub getinfo($) {
	my $challenge = shift || '';
	my $GETINFO_MSG	= chr(255) x 4 .'infoResponse'.chr(10);
	my $player_count = scalar(%players);
	my $info = "\\game\\$svars{'gamename'}\\maxPing\\$svars{'sv_maxping'}\\pure\\$svars{'sv_pure'}\\gametype\\$svars{'g_gametype'}\\sv_maxclients\\$svars{'sv_maxclients'}\\clients\\$player_count\\mapname\\$svars{'mapname'}\\sv_hostname\\$svars{'sv_hostname'}\\protocol\\$svars{'protocol'}";
	if ($challenge) { $info .= '\\challenge\\'.$challenge; }

	$sock->send($GETINFO_MSG . $info) or die("send: $!\n");
}

sub getstatus($) {
	my $challenge = shift || '';
	my $STATUS_MSG	= chr(255) x 4 .'statusResponse'.chr(10);
	my $info = '';
	my $list = '';

	if ($challenge) { $info .= '\\challenge\\'.$challenge; }

	$info .= "\\sv_allowdownload\\$svars{'sv_allowdownload'}\\g_matchmode\\$svars{'g_matchmode'}\\g_gametype\\$svars{'g_gametype'}\\sv_maxclients\\$svars{'sv_maxclients'}\\sv_floodprotect\\$svars{'sv_floodprotect'}\\g_warmup\\$svars{'g_warmup'}\\capturelimit\\$svars{'capturelimit'}\\sv_hostname\\$svars{'sv_hostname'}\\g_followstrict\\$svars{'g_followstrict'}\\fraglimit\\$svars{'fraglimit'}\\timelimit\\$svars{'timelimit'}\\g_cahtime\\$svars{'g_cahtime'}\\g_swaproles\\$svars{'g_swaproles'}\\g_roundtime\\$svars{'g_roundtime'}\\g_bombexplodetime\\$svars{'g_bombexplodetime'}\\g_bombdefusetime\\$svars{'g_bombdefusetime'}\\g_hotpotato\\$svars{'g_hotpotato'}\\g_waverespawns\\$svars{'g_waverespawns'}\\g_redwave\\$svars{'g_redwave'}\\g_bluewave\\$svars{'g_bluewave'}\\g_respawndelay\\$svars{'g_respawndelay'}\\g_suddendeath\\$svars{'g_suddendeath'}\\g_maxrounds\\$svars{'g_maxrounds'}\\g_friendlyfire\\$svars{'g_friendlyFire'}\\g_allowvote\\$svars{'g_allowvote'}\\g_armbands\\$svars{'g_armbands'}\\g_survivorrule\\$svars{'g_survivorrule'}\\g_teamnameblue\\$svars{'g_teamnameblue'}\\g_teamnamered\\$svars{'g_teamnamered'}\\g_gear\\$svars{'g_gear'}\\g_deadchat\\$svars{'g_deadchat'}\\g_maxGameClients\\$svars{'g_maxGameClients'}\\sv_dlURL\\$svars{'sv_dlURL'}\\sv_maxPing\\$svars{'sv_maxping'}\\sv_minPing\\$svars{'sv_minping'}\\sv_maxRate\\$svars{'sv_maxRate'}\\sv_minRate\\$svars{'sv_minRate'}\\dmflags\\$svars{'dmflags'}\\version\\$svars{'version'}\\protocol\\$svars{'protocol'}\\mapname\\$svars{'mapname'}\\sv_privateClients\\$svars{'sv_privateClients'}\\ Admin\\$svars{' Admin'}\\ Email\\$svars{' Email'}\\gamename\\$svars{'gamename'}\\g_needpass\\$svars{'g_needpass'}\\g_enableDust\\$svars{'g_enableDust'}\\g_enableBreath\\$svars{'g_enableBreath'}\\g_antilagvis\\$svars{'g_antilagvis'}\\g_survivor\\$svars{'g_survivor'}\\g_enablePrecip\\$svars{'g_enablePrecip'}\\g_modversion\\$svars{'g_modversion'}";

	foreach my $key (sort keys %players) {
		$list .= int($players{$key}{'score'}) .' '. int($players{$key}{'ping'}) .' "'. $players{$key}{'name'} .'"'.chr(10);
	}

	$sock->send($STATUS_MSG . $info .chr(10). $list) or die("send: $!\n");
}

sub getchallenge() {
	# not a proper challenge response
	my $response =  chr(255) x 4 .'challengeResponse '. time();
	$sock->send($response) or die("send: $!\n");
}

sub connect_proto() {
	$sock->send($CONNECT_MSG) or die("send: $!\n");
}

sub rconstatus() {
	my $list = $PRINT . 'map: '. $svars{'mapname'} .chr(10);

	$list .= 'num score ping name            lastmsg address               qport rate' . chr(10);
	$list .= '--- ----- ---- --------------- ------- --------------------- ----- -----'. chr(10);

	foreach my $key (sort keys %players) {
		$list .= sprintf("%3i %5i %4i %-18s%7i %-22s%5i %5i\n", $key, $players{$key}{'score'}, $players{$key}{'ping'}, ($players{$key}{'name'}.'^7'), $players{$key}{'lastPacketTime'}, $players{$key}{'ip'}, $players{$key}{'qport'}, $players{$key}{'rate'});
	}

	$sock->send($list . chr(10)) or die("send: $!\n");
}

sub maplist() {
	$sock->send('Not implimented yet.') or die("send: $!\n");
}

sub serverinfo() {
	my $msg1 = $SRV_INFO;
	my $msg2 = $PRINT;

	$msg1 .= sprintf("%-20s%s\n", 'sv_allowdownload', $svars{'sv_allowdownload'});
	$msg1 .= sprintf("%-20s%s\n", 'g_matchmode', $svars{'g_matchmode'});
	$msg1 .= sprintf("%-20s%s\n", 'g_gametype', $svars{'g_gametype'});
	$msg1 .= sprintf("%-20s%s\n", 'sv_maxclients', $svars{'sv_maxclients'});
	$msg1 .= sprintf("%-20s%s\n", 'sv_floodprotect', $svars{'sv_floodprotect'});
	$msg1 .= sprintf("%-20s%s\n", 'g_warmup', $svars{'g_warmup'});
	$msg1 .= sprintf("%-20s%s\n", 'capturelimit', $svars{'capturelimit'});
	$msg1 .= sprintf("%-20s%s\n", 'sv_hostname', $svars{'sv_hostname'});
	$msg1 .= sprintf("%-20s%s\n", 'g_followstrict', $svars{'g_followstrict'});
	$msg1 .= sprintf("%-20s%s\n", 'fraglimit', $svars{'fraglimit'});
	$msg1 .= sprintf("%-20s%s\n", 'timelimit', $svars{'timelimit'});
	$msg1 .= sprintf("%-20s%s\n", 'g_cahtime', $svars{'g_cahtime'});
	$msg1 .= sprintf("%-20s%s\n", 'g_swaproles', $svars{'g_swaproles'});
	$msg1 .= sprintf("%-20s%s\n", 'g_roundtime', $svars{'g_roundtime'});
	$msg1 .= sprintf("%-20s%s\n", 'g_bombexplodetime', $svars{'g_bombexplodetime'});
	$msg1 .= sprintf("%-20s%s\n", 'g_bombdefusetime', $svars{'g_bombdefusetime'});
	$msg1 .= sprintf("%-20s%s\n", 'g_hotpotato', $svars{'g_hotpotato'});
	$msg1 .= sprintf("%-20s%s\n", 'g_waverespawns', $svars{'g_waverespawns'});
	$msg1 .= sprintf("%-20s%s\n", 'g_redwave', $svars{'g_redwave'});
	$msg1 .= sprintf("%-20s%s\n", 'g_bluewave', $svars{'g_bluewave'});
	$msg1 .= sprintf("%-20s%s\n", 'g_respawndelay', $svars{'g_respawndelay'});
	$msg1 .= sprintf("%-20s%s\n", 'g_suddendeath', $svars{'g_suddendeath'});
	$msg1 .= sprintf("%-20s%s\n", 'g_maxrounds', $svars{'g_maxrounds'});
	$msg1 .= sprintf("%-20s%s\n", 'g_friendlyfire', $svars{'g_friendlyFire'});
	$msg1 .= sprintf("%-20s%s\n", 'g_allowvote', $svars{'g_allowvote'});
	$msg1 .= sprintf("%-20s%s\n", 'g_armbands', $svars{'g_armbands'});
	$msg1 .= sprintf("%-20s%s\n", 'g_survivorrule', $svars{'g_survivorrule'});
	$msg1 .= sprintf("%-20s%s\n", 'g_teamnameblue', $svars{'g_teamnameblue'});
	$msg1 .= sprintf("%-20s%s\n", 'g_teamnamered', $svars{'g_teamnamered'});
	$msg1 .= sprintf("%-20s%s\n", 'g_gear', $svars{'g_gear'});
	$msg1 .= sprintf("%-20s%s\n", 'g_deadchat', $svars{'g_deadchat'});
	$msg1 .= sprintf("%-20s%s\n", 'g_maxGameClients', $svars{'g_maxGameClients'});
	$msg1 .= sprintf("%-20s%s\n", 'sv_dlURL', $svars{'sv_dlURL'});
	$msg1 .= sprintf("%-20s%s\n", 'sv_maxPing', $svars{'sv_maxping'});
	$msg1 .= sprintf("%-20s%s\n", 'sv_minPing', $svars{'sv_minping'});
	$msg1 .= sprintf("%-20s%s\n", 'sv_maxRate', $svars{'sv_maxRate'});
	$msg1 .= sprintf("%-20s%s\n", 'sv_minRate', $svars{'sv_minRate'});
	$msg1 .= sprintf("%-20s%s\n", 'dmflags', $svars{'dmflags'});
	$msg1 .= sprintf("%-20s%s\n", 'version', $svars{'version'});
	$msg1 .= sprintf("%-20s%s\n", 'protocol', $svars{'protocol'});

	$msg2 .= sprintf("%-20s%s\n", 'mapname', $svars{'mapname'});
	$msg2 .= sprintf("%-20s%s\n", 'sv_privateClients', $svars{'sv_privateClients'});
	$msg2 .= sprintf("%-20s%s\n", ' Admin', $svars{' Admin'});
	$msg2 .= sprintf("%-20s%s\n", ' Email', $svars{' Email'});
	$msg2 .= sprintf("%-20s%s\n", 'gamename', $svars{'gamename'});
	$msg2 .= sprintf("%-20s%s\n", 'g_needpass', $svars{'g_needpass'});
	$msg2 .= sprintf("%-20s%s\n", 'g_enableDust', $svars{'g_enableDust'});
	$msg2 .= sprintf("%-20s%s\n", 'g_enableBreath', $svars{'g_enableBreath'});
	$msg2 .= sprintf("%-20s%s\n", 'g_antilagvis', $svars{'g_antilagvis'});
	$msg2 .= sprintf("%-20s%s\n", 'g_survivor', $svars{'g_survivor'});
	$msg2 .= sprintf("%-20s%s\n", 'g_enablePrecip', $svars{'g_enablePrecip'});
	$msg2 .= sprintf("%-20s%s\n", 'g_modversion', $svars{'g_modversion'});

	$sock->send($msg1) or die("send: $!\n");
	$sock->send($msg2) or die("send: $!\n");
}

sub dumpuser(@) {
	my @cmd = shift || undef;
	if (!@cmd) { print 'Null value passed.'; return; }

	if (!@cmd[6]) {
		$sock->send($DUSER_USAGE) or die("send: $!\n");
		return;
	}
}

sub fdir(@) {
	my @cmd = shift || undef;
	if (!@cmd) { print 'Null value passed.'; return; }

	if (!@cmd[6]) {
		$sock->send($FDIR_USAGE) or die("send: $!\n");
		return;
	}

	if (@cmd[6] eq '*.bsp') {
		# maplist
		return;
	}
}

sub dir(@) {
	my @cmd = shift || undef;
	if (!@cmd) { print 'Null value passed.'; return; }

	if (!@cmd[6]) {
		$sock->send($DIR_USAGE) or die("send: $!\n");
		return;
	}	
}

sub create_svars() {
	$svars{' Admin'} = 'test';
	$svars{' Email'} = 'test@test.com';
	$svars{'capturelimit'} = '0';
	$svars{'dmflags'} = '13';
	$svars{'fraglimit'} = '150';
	$svars{'g_RoundTime'} = '3';
	$svars{'g_allowchat'} = '1';
	$svars{'g_allowvote'} = '0';
	$svars{'g_antilagvis'} = '0';
	$svars{'g_antiwarp'} = '1';
	$svars{'g_antiwarptol'} = '50';
	$svars{'g_armbands'} = '0';
	$svars{'g_bluewave'} = '15';
	$svars{'g_bombdefusetime'} = '10';
	$svars{'g_bombexplodetime'} = '40';
	$svars{'g_bulletPredictionThreshold'} = '5';
	$svars{'g_cahtime'} = '60';
	$svars{'g_captureScoreTime'} = '';
	$svars{'g_deadchat'} = '2';
	$svars{'g_enableBreath'} = '0';
	$svars{'g_enableDust'} = '0';
	$svars{'g_enablePrecip'} = '0';
	$svars{'g_failedvotetime'} = '60';
	$svars{'g_flagreturntime'} = '30';
	$svars{'g_followEnemy'} = '0';
	$svars{'g_followForced'} = '0';
	$svars{'g_followstrict'} = '1';
	$svars{'g_forcerespawn'} = '3';
	$svars{'g_friendlyFire'} = '1';
	$svars{'g_gametype'} = '3';
	$svars{'g_gear'} = '0';
	$svars{'g_gravity'} = '800';
	$svars{'g_hotpotato'} = '2';
	$svars{'g_inactivity'} = '180';
	$svars{'g_knockback'} = '1000';
	$svars{'g_log'} = 'games.log';
	$svars{'g_loghits'} = '0';
	$svars{'g_logroll'} = '0';
	$svars{'g_logsync'} = '1';
	$svars{'g_maintainTeam'} = '1';
	$svars{'g_mapcycle'} = 'mapcycle.txt';
	$svars{'g_matchmode'} = '0';
	$svars{'g_maxGameClients'} = '0';
	$svars{'g_maxrounds'} = '0';
	$svars{'g_maxteamkills'} = '3';
	$svars{'g_modversion'} = '4.1';
	$svars{'g_motd'} = 'Welcome to the fake server.';
	$svars{'g_needpass'} = '0';
	$svars{'g_password'} = '';
	$svars{'g_pauselength'} = '0';
	$svars{'g_precipAmount'} = '';
	$svars{'g_redwave'} = '15';
	$svars{'g_refNoBan'} = '';
	$svars{'g_refPass'} = '';
	$svars{'g_referee'} = '0';
	$svars{'g_removeBodyTime'} = '';
	$svars{'g_respawndelay'} = '3';
	$svars{'g_respawnProtection'} = '2';
	$svars{'g_roundtime'} = '3';
	$svars{'g_suddendeath'} = '1';
	$svars{'g_survivor'} = '0';
	$svars{'g_survivorrule'} = '0';
	$svars{'g_swaproles'} = '0';
	$svars{'g_teamForceBalance'} = '0';
	$svars{'g_teamautojoin'} = '0';
	$svars{'g_teamkillsforgettime'} = '180';
	$svars{'g_teamnameblue'} = 'Blue Team';
	$svars{'g_teamnamered'} = 'Red Team';
	$svars{'g_timeoutlength'} = '240';
	$svars{'g_timeouts'} = '3';
	$svars{'g_warmup'} = '15';
	$svars{'g_waverespawns'} = '0';
	$svars{'gamename'} = 'q3ut4';
	$svars{'logfile'} = '2';
	$svars{'mapname'} = 'nomap';
	$svars{'protocol'} = '68';
	$svars{'rconpassword'} = $RCON_PW;
	$svars{'sv_allowdownload'} = '0';
	$svars{'sv_battleye'} = '0';
	$svars{'sv_cheats'} = '0';
	$svars{'sv_dlURL'} = '';
	$svars{'sv_floodprotect'} = '1';
	$svars{'sv_hostname'} = 'Fake UrT Server';
	$svars{'sv_joinmessage'} = 'Welcome';
	$svars{'sv_master1'} = '';
	$svars{'sv_master2'} = 'master.urbanterror.net';
	$svars{'sv_master3'} = 'master2.urbanterror.net';
	$svars{'sv_master4'} = 'master.quake3arena.com';
	$svars{'sv_master5'} = '';
	$svars{'sv_maxRate'} = '0';
	$svars{'sv_maxclients'} = '20';
	$svars{'sv_maxping'} = '350';
	$svars{'sv_minRate'} = '0';
	$svars{'sv_minping'} = '0';
	$svars{'sv_privateClients'} = '4';
	$svars{'sv_privatePassword'} = '';
	$svars{'sv_pure'} = '0';
	$svars{'sv_strictauth'} = '0';
	$svars{'sv_timeout'} = '180';
	$svars{'sv_zombietime'} = '2';
	$svars{'timelimit'} = '20';
	$svars{'version'} = 'ioq3 1.35urt linux-i386 Dec 20 2007';
}


sub load_test($) {
	my $filename = shift;
	my $fh = new FileHandle;
	my $read = '';
	my $old_rec_sep = $/;

	$fh->open("<$filename") or die("Could not open file. \n$!\n");
	
	while  (my $line = $fh->getline()) {

		if ($line =~ m/^\/\//o) { next; }	# Ignore comments

		if ($/ eq ");\n") {
			$read .= $line;
			$/ = $old_rec_sep;
			next;
		}

		if (($line =~ m/^%players/o) || $line =~ m/^\@playerlist/o) {
			$read .= $line;

			if ($line !~ m/\);$/o) {
				$/ = ");\n";
			}
			next;
		}

		if ($line =~ m/^\s*\$svars\{[^;\\]+;\s*$/o) {
			$read .= $line;
		}

	}
	$/ = $old_rec_sep;
	$fh->close;

	eval $read; # This is rather unsafe...
	die if $@;
}

sub update_test() {
	my ($range, $min, $rand);

	if ($stats{'total_packets'} % 2) {
		$rand = int(rand(10));
		if ($rand == 0) {
			foreach my $key (keys %players) {
				delete $players{$key};
				last;	
			}
		}
		
		if ($rand > 7 && ((scalar %players) < $svars{'sv_maxclients'}) ) {
			if (@playerlist) {
				for (0 .. $svars{'sv_maxclients'}) {
					if (!$players{$_}) {
						$players{$_} = pop @playerlist;
						if ($opt_verbose > 1) { print @playerlist . " left\n"; }
						last;
					}
				}
			}
		}

		foreach my $key (sort keys %players) {
			if (exists $players{$key}{'__test'}) {
				if (exists $players{$key}{'__test'}{'rand_ping'}) {
					$range	= int($players{$key}{'__test'}{'rand_ping'}{'range'});
					$min	= int($players{$key}{'__test'}{'rand_ping'}{'min'});
					$players{$key}{'ping'} = int(rand($range)-$min);
				}
				if (exists $players{$key}{'__test'}{'rand_score'}) {
					$range	= int($players{$key}{'__test'}{'rand_score'}{'range'});
					$min	= int($players{$key}{'__test'}{'rand_score'}{'min'});
					$players{$key}{'score'} = int(rand($range)-$min);
				}
			}
		}
	}
}

sub rand_string($) {
	my $len = shift || 8;
	my @chars = ('a'..'z','A'..'Z','0'..'9',qw(` ~ ! @ # $ % ^ & * - _ + = [ ] { } | : ' < > , . / ?),'(','\)');
	return join('', map $chars[rand @chars], 1..$len );
}

sub rand_guid() {
	my @chars = ('A'..'Z','0'..'9');
	return join('', map $chars[rand @chars], 1..32 );
}

sub rand_ip() {
	return join ('.', int(rand(255)), int(rand(255)), int(rand(255)), int(rand(255)) );
}

sub random_playerlist() {
	for (1..$opt_random) {
		my $temp = {
			'name'	=> rand_string(16),
			'ip'	=> rand_ip() .':27960',
			'qport'	=> int(rand(2**16)),
			'ping'	=> int(rand(400)),
			'score'	=> int(rand(125) - 5),
			'rate'	=> 8000,
			'gear'	=> 'FaJOUAA',
			'cl_guid'	=> rand_guid(),
			'lastPacketTime'=> 0,
			'ut_timenudge'	=> 0,
			'__test'=> {	'rand_ping' =>	{'range' => int(rand(20)), 'min' => int(rand(10) - 5)},
					'rand_score'=>	{'range' => int(rand(10)), 'min' => int(rand(6) - 3)}}
		};
		push(@playerlist, $temp)
	}
}
