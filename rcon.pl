#!/usr/bin/perl
# vim:nu:ai:si:noet:ts=8:sw=8
#------------------------------------------------------------------------------
#	Rcon Monitoring Script	[RAD or something or other]
#	Date:	August/September 2009
#	Author:	Jeff Genovy (jgen)
#	This code is released under a BSD style license.
#	( see LICENSE.txt file for details )
#------------------------------------------------------------------------------

use strict;
use warnings;
use Data::Dumper;			# To be removed later
$Data::Dumper::Sortkeys = 1;		# Sort the output of hashes by default

use POSIX qw/strftime/;			# date/time formatting
use Socket;				# Communicating with ioUrbanTerror Server
use DBI;				# For database access
    
require './urt_common.pl';		# Not currently used fully, maybe later on [useful for stats]

# Output to a log file to assist with debugging
# - Problems were occuring with 'null' player names after running the script for several hours
close(STDOUT);
close(STDERR);

open (STDOUT, '>>', "/tmp/urtrad_log") or die "Can't redirect STDOUT: $!";
open (STDERR, ">&STDOUT")     or die "Can't dup STDOUT: $!";

select STDERR; $| = 1; # make unbuffered
select STDOUT; $| = 1; # make unbuffered


# ----- Database Configuration -------
# TODO: centralized config for database - shared between rcon.pl and interface.php
my $db_driver		= 'SQLite';#'mysql';
my $db_host 		= 'localhost';
my $db_port		= '13390';
my $db_database		= 'test_db.db';#'urt_rad';
my $db_user		= '';#'rconlogs';
my $db_pass		= '';#'urtlogs';


# ----- Urban Terror Sever Variables ------
my $urt_server		= 0;
my $urt_port		= 0;
my $urt_proto		= getprotobyname('udp');
my $urt_rcon_pw		= '';
my $urt_addr		= '';
my $urt_svars		= '';

my $server_id			= 0;
my $timeouts			= 0;
my $timeout_last		= 0;
my $timeout_delay		= 5;
my $timeout_wait_delay		= 10;


# ----- Status -----
my $backend_status		= 0;
my $client_request		= 0;
my $log_lines_processed		= 0;
my $log_bytes_processed		= 0;
my $log_last_check		= 0;
my $log_check_delay		= 25;
my $last_update			= '';


# ----- Globals -----
my $main_status			= 1;
my $need_rcon_poll		= 1;
my $just_rcon_polled		= 0;

my %main_player_hash		= ();
my %secondary_player_hash	= ();
my %connecting_players		= ();
my %map_list_hash		= ();


# ----- Error Messages -----
my %errors = (
	-1	=> 'Could not open a socket.',
	-2	=> 'Could not connect to external address.',
	-3	=> 'Could not send message to server.',
	-4	=> 'Error recieving data from server.',
	-5	=> 'Server did not respond - request timed out.',
	-6	=> 'Could not close the socket.',
	-10	=> 'Bad rcon password.',
	-11	=> 'The server did not recognize the command.',
	-12	=> 'No rcon password set yet.',
	-13	=> 'Server config is missing or incorrect.'
);
# -----------


############ Start of Execution #############

#-- Check if we can connect to that type of database -----------
my %server_drivers = map {$_, 1} DBI->available_drivers();
if ( !exists $server_drivers{$db_driver} ) {
	die ('No driver is currently installed for a "'. $db_driver. '" database.'."\n"); }

if ($db_driver ne 'SQLite') {
	if (!inet_aton($db_host)) {
		die ('Could not resolve database host "'. $db_host .'".'."\n"); }

	if (int($db_port) > 65535 || int($db_port) < 0) {
		die ('Invalid port ['. $db_port .'] specified for database server.'."\n"); }

	if (!length($db_database)) {
		die ('No database specified for the program to use.'); }

	if (!length($db_user)) {
		die ('No user name set for database access.');	}

	if (!length($db_pass)) {
		print 'Using an empty password. Consider setting a password for more security.'."\n"; }
}
#----------------


# ---- Setup global database connector variables ----
my $dsn = '';
if ($db_driver eq 'SQLite') {
	$dsn = "dbi:SQLite:dbname=$db_database";
} else {
	$dsn = "dbi:$db_driver:database=$db_database;host=$db_host;port=$db_port";;
}
my $dbhandle = DBI->connect($dsn, $db_user, $db_pass) 
	or die("Unable to connect to the database.\n". DBI->errstr ."\n");

	
# Called on program termination
END {
	print "< Program Terminated >\n";
	if ($dbhandle) {
		print "Disconnecting from database...\n";
		$dbhandle->disconnect();
	}
	dump_debug();
	print "\n< END >\n";
}


######## Subroutines ########

sub dump_debug() {
	# Dump debug information
	print "\n" . '-' x 40 . "\n";
	print '-->  Dumping Debug Information:';
	
	print "     main_status = " . $main_status . "\n";
	print "  need_rcon_poll = ". $need_rcon_poll . "\n";
	print "just_rcon_polled = ". $just_rcon_polled . "\n";
	
	print "--> main_player_hash:\n";
	warn Dumper \%main_player_hash;
	print "--> secondary_player_hash:\n";
	warn Dumper \%secondary_player_hash;
	print "--> connecting_players:\n";
	warn Dumper \%connecting_players;
	print "--> map_list_hash:\n";
	warn Dumper \%map_list_hash;
	
	print "\n" . '-' x 40 . "\n";
}

sub db_getStatus() {
	my $status_query = "SELECT * FROM `status`";
	my $status_query_hndl = $dbhandle->prepare($status_query)
		or die("Unable to prepare query.\n". $dbhandle->errstr ."\n");
	$status_query_hndl->execute()
		or die("Unable to execute query.\n". $status_query_hndl->errstr ."\n");

	my $status = $status_query_hndl->fetchrow_hashref();

	if (!$status) {
		# If there is nothing in the `status` table, then we will create an entry.
		$backend_status = -13;
		$client_request = 0;
		$log_lines_processed = 0;
		$log_bytes_processed = 0;
		$log_last_check = 0;
		$last_update = $dbhandle->quote( strftime("%F %T", localtime) );
		
		$dbhandle->do('INSERT INTO `status` (backend_status,client_request,log_lines_processed,log_bytes_processed,log_last_check,last_update) VALUES ('."$backend_status, $client_request, $log_lines_processed, $log_bytes_processed, $log_last_check, $last_update )")
			or die('Unable to execute query.');
	} else {
		# Set the Global Status Variables
		$backend_status		= int(${$status}{backend_status}) || 0;
		$client_request 	= int(${$status}{client_request}) || 0;
		$log_lines_processed	= int(${$status}{log_lines_processed}) || 0;
		$log_bytes_processed	= int(${$status}{log_bytes_processed}) || 0;
		$log_last_check		= int(${$status}{log_last_check}) || 0;
		#$log_check_delay	= int(${$status}{log_check_delay});
		$last_update		= ${$status}{last_update};
	}
	$status_query_hndl->finish();
}

sub db_getServerInfo() {
	my $servers_query = "SELECT * FROM `servers`";
	my $servers_query_hndl = $dbhandle->prepare($servers_query)
		or die("Unable to prepare query.\n". $dbhandle->errstr ."\n");
	$servers_query_hndl->execute()
		or die("Unable to execute query.\n". $servers_query_hndl->errstr ."\n");

	my $servers = $servers_query_hndl->fetchrow_hashref();
	
	if (!$servers) {
		# If there is nothing in the `servers` table, then we really can't do anything except wait...
		$backend_status = -13;
		# Reset other important Global variables to some defaults
		$server_id		= 0;
		$urt_server		= 0;
		$urt_port		= 0;
		$urt_rcon_pw		= '';
		$urt_addr		= '';
		$timeout_delay		= 6;
		$timeout_wait_delay	= 12;
	} else {
		#Set the Urban Terror Sever Global Variables
		$urt_server		= inet_aton( ${$servers}{ip} );
		$urt_port		= int(${$servers}{port}) || 27960;
		$urt_rcon_pw		= ${$servers}{rcon_pw};
		$urt_addr		= sockaddr_in($urt_port, $urt_server);
		
		$server_id		= int(${$servers}{server_id});
		$timeouts		= int(${$servers}{timeouts}) || 0;
		$timeout_delay		= int(${$servers}{timeout_delay}) || 5;
		$timeout_last		= int(${$servers}{timeout_last}) || 0;
		$timeout_wait_delay	= int(${$servers}{timeout_wait_delay}) || 10;
	}
	$servers_query_hndl->finish();
}

sub db_getMapList() {
	my $map_qry = 'SELECT * FROM `maps`';
	my $map_qry_hndl = $dbhandle->prepare($map_qry) or die("Unable to prepare query.\n". $dbhandle->errstr ."\n");
	$map_qry_hndl->execute() or die("Unable to execute query.\n". $map_qry_hndl->errstr ."\n");

	my $rows = $map_qry_hndl->rows();

	if (!defined($rows) || $rows < 1) {
		# no maps in the database map listing.
		if ($backend_status == 0) {
			# Just staring up 
			warn "No maps found in the database.";
		}

		# Query the server to get a full listing of maps files on the sever
		urt_getMapList();
	} else {
		foreach ($rows) {
			my @map = $map_qry_hndl->fetch();

			if (!@map) {
				warn "An error occured while retrieving the map list from the database..";
			} else {
				# make an entry in the map list hash
				if ($map[1] && $map[2]) {
					$map_list_hash{$map[1]} = $map[2];
				} else {
					warn "There is a problem with the map table in the database.";
				}
			}
		}
	}
	$map_qry_hndl->finish();
}

sub urt_queryServer($) {
	my $query = shift;
	my $incoming = '';
	my $msg = '';
	my $who;	# Stores the ip address and port of the computer that responded. - Not Used
				#  - could unpack & check to verify the actual _requested ip_ responded...
				#     ie: check for icmp redirects and such

	# Open up a socket to send out our request
	socket (hndl_sock, PF_INET, SOCK_DGRAM, $urt_proto) 		or return -1;
	connect (hndl_sock, $urt_addr)					or return -2;
	send (hndl_sock, $query, 0, $urt_addr)				or return -3;

	vec( (my $rin=''), fileno(hndl_sock), 1 ) = 1;

	if ( select($rin, undef, undef, $timeout_delay) ) {
			( $who = recv (hndl_sock, $incoming, 9999, 0) )	or return -4;
	} else { 							   return -5;}

	# All messages from the ioQuake engine end with a newline.
	# If the incoming message did not end with a newline, then try to recieve the next packet.
	# - For example: 'rcon status' replies from a server with 14+ players is often sent in 2 packets)
	while ($incoming !~ /\n$/) {
		#warn ">>waiting for another packet...";
		if ( select($rin, undef, undef, $timeout_delay) ) {
			( $who = recv (hndl_sock, $msg, 9999, 0) )	or return -4;
		} else { 						   return -5;}
		$incoming .= $msg;
	}

	close hndl_sock							or return -6;
	return $incoming;
}

sub urt_rconStatus() {
	print 'Requesting rcon status update at ('. localtime() .").\n";

	my $msg = chr(255) x 4 . 'rcon '. $urt_rcon_pw ." status\n";
	my $result = urt_queryServer($msg);

	if ( length($result) < 29 ){
		urt_serverError($result);
	} else {	#-------------------- Got Sever Response --------------------
		$backend_status	= 1;
		$just_rcon_polled = 1;
		$need_rcon_poll	= 0;
	
		# Remove the old list of players from the database.
		$dbhandle->do('DELETE FROM `current_players`') or die('Unable to execute query.');
		
		# Only delete the players from the list that _were actually connected_. (ie: they had a slot number)
		foreach (keys %secondary_player_hash) {
			if (exists($secondary_player_hash{$_}->{slot})	){
				delete $secondary_player_hash{$_};
			}
		}
		
		$result =~ s/\xFF\xFF\xFF\xFFprint\n//go;	# Clean up the server response
		
		my @reply = split(/\n/o, $result);
		my @pvars;
		
		if (@reply > 3) {	# Check if there are any players on the server
			my $tmp_str = '';
			my $name = '';
		
			foreach( @reply[3..$#reply] ) {
		
				if ($_ =~ m/^ *(\d+) +(-{0,1}\d+) +(\d+) +(.+?)\^7 +(\d+) ([\d\.]+):(\d+) +(\d+) +(\d+)$/o) {
					@pvars = (0,$1,$2,$3,$4,$5,$6,$7,$8,$9);
					
					$name = $4;
					$name =~ s/^\s+|\s+$//o;	# Trim leading and trailing whitespace
					
					if ($name eq '') { $name = ';NULL'; }	# This is pretty much a hack to cover players with no name (null length string)
					
					$tmp_str .= ",($pvars[1],$pvars[2],$pvars[3],".$dbhandle->quote($name).",INET_ATON('$pvars[6]'),$pvars[8],$pvars[9])";
					
					$secondary_player_hash{$name} ={slot	=> $pvars[1],
									score	=> $pvars[2],
									ping	=> $pvars[3],
									ip	=> $pvars[6],
									qport	=> $pvars[8],
									rate	=> $pvars[9] }
				}
			}
			substr($tmp_str, 0, 1) = "";	# removes the first comma in tmp_str
			
			$dbhandle->do('INSERT INTO `current_players` (slot_num,score,ping,name,ip,qport,rate) VALUES '. $tmp_str)
				or die("Unable to execute query.\n\n$tmp_str");
			
		} else {
			print "No players connected to the server\n"; }
	}
}

sub urt_getStatus() {
	my $msg = chr(255) x 4 . "getstatus\n";
	my $result = urt_queryServer($msg);

	if ( length($result) < 29 ){
		urt_serverError($result);
	} else {	#-------------------- Got Sever Response --------------------
		my @reply = split(/\n/o, $result);
		
		if ($reply[1] ne $urt_svars ) {		# if the server config vars have changed
			if ($just_rcon_polled) {
				$urt_svars = $reply[1];		# update the svar string
				db_updateServer();		# update the server info in the database
			} else {
				warn "- Server vars have changed.";
				$need_rcon_poll = 1;
				#return;		# We don't need to return right away...
			}
		}
		$just_rcon_polled = 0;
		
		# Only delete players from the list that are NOT actually connected.
		#  ie: have no slot, or are in 'connecting' hash.
		foreach (keys %secondary_player_hash) {
			if (!exists($secondary_player_hash{$_}->{slot})	){
				delete $secondary_player_hash{$_}; } }

		foreach (keys %connecting_players) {
			delete $secondary_player_hash{$_}; }
		
		# Temporary variables
		my $name = '';
		my $ping = 0;
		my $score = 0;
		my @players = @reply[2..$#reply];		# store the players in a new array

		if (scalar(@players) != scalar(keys %secondary_player_hash)) {
			# We have a different number of players compared to last time
			print "Number of players changed.";
			print "\t array: ", scalar(@players), " hash: ", scalar(keys %secondary_player_hash), "\n";
			$need_rcon_poll = 1;
		}
		
		foreach ( @players ) {
			$_ =~ m/^(-{0,1}\d+) (\d+) "([^\"]*)"$/o;
			
			$score	= $1;
			$ping	= $2;
			$name	= $3;
			$name	=~ s/^\s+|\s+$//o;	# Trim leading and trailing whitespace

			if ($name eq '') { $name = ';NULL'; }	# This is pretty much a hack to cover players with no name (null length string)
			
			if ( !exists($secondary_player_hash{$name}) ) {
				print " New name: ". $name ."\n";
				$need_rcon_poll = 1;	# new player name found: request rcon update
			}
			# If this player was 'connecting' last time but has a valid ping now, remove them from 'connecting' hash and request rcon update.
			if ( exists($connecting_players{$name}) && $ping != 999 ) {
				delete $connecting_players{$name};
				$need_rcon_poll = 1;
			}

			# Update the list of players with the new information...
			$secondary_player_hash{$name}->{score}	= $score;
			$secondary_player_hash{$name}->{ping}	= $ping;
			$name = $dbhandle->quote($name);
			
			$dbhandle->do('UPDATE `current_players` SET score='.$score.',ping='.$ping.' WHERE name='. $name);
		}
	}
}

sub urt_getMapList() {
	# retrieve the full map listing from the server.
	warn "Requesting full map list from server....\n";

	my $msg = chr(255) x 4 . 'rcon '. $urt_rcon_pw ." fdir *.bsp\n";
	my $result = urt_queryServer($msg);

	if ( length($result) < 29 ){
		urt_serverError($result);
	} else {	#--------------- Got Sever Response ---------------
		my @reply = split(/\n/o, $result);
		
		if (@reply < 3) {
			warn "Error: It looks like there are no maps on the server.";
		} else {
			foreach (@reply) {
				if ($_ =~ m/^\w+?\/(\w+?)\.bsp$/o) {
					# Make an entry in the map list hash if not listed.
					if (($1) && !exists( $map_list_hash{$1} )) {
						$map_list_hash{$1} = 0;
					}
				}
			}
		}
	}
}

sub changeName($$$) {
	my $old		= shift || undef;	# Old player name
	my $new		= shift || undef;	# New player name
	my $time	= shift || time();
	
	if (!$old || !$new) {
		warn "Error: A Null player name was passed to changeName() ";
		return; }
	
	my $ip		= $main_player_hash{$old}->{ip};
	my $name	= $dbhandle->quote($new);		# escape the new name

	# Check if we have seen that Name before
	my $name_qry = 'SELECT * FROM `players` WHERE name='. $name;
	my $name_qry_hndl = $dbhandle->prepare($name_qry) or die("Unable to prepare query.\n". $dbhandle->errstr ."\n");
	$name_qry_hndl->execute() or die("Unable to execute query.\n". $name_qry_hndl->errstr ."\n");
	my $name_results = $name_qry_hndl->fetchrow_arrayref();
	
	# Name Check
	if ($name_qry_hndl->rows > 1) {
		# Name listed in the players table more then once... this should _Not happen_ if the database is setup correctly
		warn "-> Duplicate Name entries in 'players' table... ";
		return;
	} elsif ($name_qry_hndl->rows == 1) {
		# Name is listed in the players table
		$main_player_hash{$old}->{player_id}	= @{$name_results}[0];	# Store the new player_id
		$main_player_hash{$old}->{duration}	= @{$name_results}[2];	# Store the new player duration
	} else {
		# We have not seen this name before...
		warn "New player name, adding to database...\n";
		# Create a new entry in the players table
		$dbhandle->do('INSERT INTO `players` (name,duration,creation) VALUES ('.$name.', 0, FROM_UNIXTIME('. $time .') )')
		or die("Unable to execute query.\n". $dbhandle->errstr ."\n");

		my $name_qry2 = 'SELECT * FROM `players` WHERE name='. $name;
		my $name_qry2_hndl = $dbhandle->prepare($name_qry2) or die("Unable to prepare query.\n". $dbhandle->errstr ."\n");
		$name_qry2_hndl->execute() or die("Unable to execute query.\n". $name_qry2_hndl->errstr ."\n");
		my $name_results2 = $name_qry2_hndl->fetchrow_arrayref();
		
		$main_player_hash{$old}->{player_id}	= @{$name_results2}[0];	# Store the player_id
		$main_player_hash{$old}->{duration}	= 0;			# Zero the duration as its a new name;
		$name_qry2_hndl->finish();
	}
	$name_qry_hndl->finish();

	# Store the Player ID
	my $player_id = $main_player_hash{$old}->{player_id};

	# IP Check
	my $ips_qry = 'SELECT * FROM `ips` WHERE player_id='. $player_id .' AND ip=INET_ATON("'. $ip .'")';
	my $ips_qry_hndl = $dbhandle->prepare($ips_qry) or die("Unable to prepare query.\n". $dbhandle->errstr ."\n");
	$ips_qry_hndl->execute() or die("Unable to execute query.\n". $ips_qry_hndl->errstr . "\n");
	my $ips_results = $ips_qry_hndl->fetchrow_arrayref();

	if ($ips_qry_hndl->rows > 1) {
		warn "-> Duplicate entries in the 'ips' table... ";
		return;
	} elsif ($ips_qry_hndl->rows == 1) {
		# Player has been seen with this ip before
		# - nothing really to do..
	} else {
		# New ip for this player name
		$dbhandle->do('INSERT INTO `ips` (ip,ip_text,player_id,creation) VALUES (INET_ATON("'.$ip.'"),"'.$ip.'",'.$player_id.',FROM_UNIXTIME('. $time .') )')
			or die("Unable to execute query.\n". $dbhandle->errstr ."\n");
	}
	$ips_qry_hndl->finish();
}

sub newPlayer($$) {
	# Check the database for existing entries that match the IP / Name and update them Or create new entries.
	# Also: Add a new player to the main_player_hash
	my $player	= shift;
	my $time	= shift || time();		# store the time we detected them
	
	if (!$player) {
		warn "Error: A Null player name was passed to newPlayer() ";
		return;	}
	
	my $ip		= $secondary_player_hash{$player}->{ip};	# human readable ip address
	
	if (!$ip) {
		warn "Error: The player passed to newPlayer() does not have an IP address. ";
		return; }

	my $name	= $dbhandle->quote($player);	# escape the name for safe database useage
	my $playerid	= 0;				# pulled in from the database
	my $duration	= 0;				# duration's default value is zero

	printf("> Checking IP:%15s\tName: %-20s\t", $ip, $player);
	
	# Check if we have seen that Name before
	my $name_qry = 'SELECT * FROM `players` WHERE name='. $name;
	my $name_qry_hndl = $dbhandle->prepare($name_qry) or die("Unable to prepare query.\n". $dbhandle->errstr ."\n");
	$name_qry_hndl->execute() or die("Unable to execute query.\n". $name_qry_hndl->errstr ."\n");
	my $name_results = $name_qry_hndl->fetchrow_arrayref();
	
	# Name Check
	if ($name_qry_hndl->rows > 1) {
		# Name listed in the players table more then once... this should _Not happen_ if the database is setup correctly
		warn "-> Duplicate Name entries in 'players' table... ";
		return;
	} elsif ($name_qry_hndl->rows == 1) {
		# Found player name in the table
		$playerid = @{$name_results}[0];
		$duration = @{$name_results}[2];
	} else {
		# We have not seen this name before...
		print 'New name, adding to database...'."\n";
		# Create a new entry in the players table
		$dbhandle->do('INSERT INTO `players` (name,duration,creation) VALUES ('.$name.',0,FROM_UNIXTIME('.$time.'))')
			or die("Unable to execute query.\n". $dbhandle->errstr ."\n");

		# Now retrieve the player_id from the newly created entry
		my $name_qry2 = 'SELECT * FROM `players` WHERE name='. $name;
		my $name_qry2_hndl = $dbhandle->prepare($name_qry2) or die("Unable to prepare query.\n". $dbhandle->errstr ."\n");
		$name_qry2_hndl->execute() or die("Unable to execute query.\n". $name_qry2_hndl->errstr ."\n");
		my $name_results2 = $name_qry2_hndl->fetchrow_arrayref();
		
		$playerid = @{$name_results2}[0];
		$name_qry2_hndl->finish();
	}
	$name_qry_hndl->finish();

	# Store the information in the hash (will be copied to the main hash later on)
	$secondary_player_hash{$player}->{player_id}	= $playerid;
	$secondary_player_hash{$player}->{duration}	= $duration;
	$secondary_player_hash{$player}->{time}		= $time;	# time player was detected


	# Check if we have seen that IP before
	my $ip_qry = 'SELECT * FROM `ips` WHERE ip=INET_ATON("'. $ip .'") AND player_id='. $secondary_player_hash{$player}->{player_id};
	my $ip_qry_hndl = $dbhandle->prepare($ip_qry) or die("Unable to prepare query.\n". $dbhandle->errstr ."\n");
	$ip_qry_hndl->execute() or die("Unable to execute query.\n". $ip_qry_hndl->errstr ."\n");
	my $ip_results = $ip_qry_hndl->fetchrow_arrayref();

	# IP Address Check
	if ($ip_qry_hndl->rows > 1) {
		# IP AND Player_ID is listed more then once... this should _Not happen_ if the database is setup correctly
		warn "-> Duplicate IP entries in 'ips' table... ";
		return;
	} elsif ($ip_qry_hndl->rows == 1) {
		# The IP AND Player_ID are listed in the table
		# - we have seen this IP with this Name before.
		print 'Welcome back: '. $player ."\n";
	} else {
		# We have not seen that IP AND player name together before...
		# Create a new entry in the ips table
		$dbhandle->do('INSERT INTO `ips` (ip,ip_text,player_id,creation) VALUES (INET_ATON("'.$ip.'"),"'.$ip.'",'.$secondary_player_hash{$player}->{player_id}.',FROM_UNIXTIME('.$time.'))')
			or die("Unable to execute query.\n". $dbhandle->errstr ."\n");
	}
	$ip_qry_hndl->finish();

	
	# Add an entry to the 'rcon_log' table
	$dbhandle->do('INSERT INTO `rcon_log` (datetime,player_id,ip,slot,action) VALUES (FROM_UNIXTIME('. $time .'),'.$secondary_player_hash{$player}->{player_id}.',INET_ATON("'. $ip .'"),'.$secondary_player_hash{$player}->{slot}.',1)')
		or die("Unable to execute query.\n". $dbhandle->errstr ."\n");


	# Now that all the database stuff is taken care of, copy over the information on the player into the main players hash
	$main_player_hash{$player} = {};		# Make a key for them...
	
	foreach (keys %{$secondary_player_hash{$player}} )		# ...and load it with all the information we have on them.
		{ $main_player_hash{$player}->{$_} = $secondary_player_hash{$player}->{$_}; }
	
	# Remove them from the list of 'connecting players' [if they are in that list] since they have now fully connected to the server.
	if (exists($connecting_players{$player})) {
		delete $connecting_players{$player}; }
}

sub db_doPlayerStats() {
	my $time = time();		# Store the current time ( for creating database entries and disconnects )

	if ($main_status == 1) {		# On script startup we add all the players found on the server.
		foreach my $player (keys %secondary_player_hash) {
			newPlayer($player, $time); }
		$main_status = 2;
		return;						# and thats it - there isn't much else to do.
	}

	# I.) First we process the new list of players...

	# Last update was a rcon status()
	if ($just_rcon_polled > 0) {

		foreach my $player (keys %secondary_player_hash) {
		
			if ((keys %{$secondary_player_hash{$player}}) < 3) {
				# This player is still "Connecting..." and is not listed in rcon status yet.
				warn "Player: $player is connecting...";
				# I suppose we could add the name to the players table. but we would have no IP to go with it....
				# So we store the name in a temporary hash of 'connecting players'
				# And check if they are fully connected next time, or have disappeared/disconnected.
				$connecting_players{$player} = 1;
				next; }
				
			if ( !exists($main_player_hash{$player}) ) {
				
				if (scalar( keys %main_player_hash ) == 0) {
					warn "New player joined empty server.";	#New player has joined empty server
					newPlayer($player, $time);
				} else {
					foreach my $old (keys %main_player_hash) {
						if ( ($main_player_hash{$old}{ip} eq $secondary_player_hash{$player}{ip}) && ($main_player_hash{$old}{slot} == $secondary_player_hash{$player}{slot}) ) {
							# If the ip AND the slot are the same
							# then it's the same player - they just changed their name
							warn "Player: '$old' changed name to '$player'\n";
							changeName($old, $player, $time);

							$main_player_hash{$player} = {};	# Make a new key for their new name.
							# Copy over their old data
							foreach (keys %{$main_player_hash{$old}})
									{ $main_player_hash{$player}->{$_} = $main_player_hash{$old}->{$_}; }
							delete $main_player_hash{$old};		# Delete the old key with their old name.
						}
					}
					# if they still don't exist in the old list, then they truly are a new player
					if ( !exists($main_player_hash{$player}) ) {
						warn "New player has joined.";	# A new player has joined the server
						newPlayer($player, $time);
					}
				}
			} else {
				if (!exists($main_player_hash{$player}{ip})) {
					# There is already an entry in the main hash for this player, but no ip.
					# We have an ip now, so let's add the player again to the main hash.
					newPlayer($player, $time);
				} else {
					if ( ($main_player_hash{$player}->{ip} ne $secondary_player_hash{$player}->{ip}) || ($main_player_hash{$player}->{slot} ne $secondary_player_hash{$player}->{slot}) ) {
						# IF the ip AND the slot are different but the name is the same
						# then we missed a disconnect AND a join.
						warn "Error: New player detected with previously used name.\nWe have missed a player 'Disconnect' And a player 'Join'\n";
						warn "Perhaps the time between status updates is too long?...";
						warn 'Debug information: ';
						warn Dumper $player;
						warn Dumper 'main hash:' , $main_player_hash{$player};
						warn Dumper 'second hash:' , $secondary_player_hash{$player};
					}
				}
			}
		}
	} else {
		# Last update was just a getStatus()
		# Only check if next update is not going to be an rcon update.
		if ($need_rcon_poll == 0) {
			foreach my $player (keys %secondary_player_hash) {
				if ( !exists($main_player_hash{$player}) && !exists($connecting_players{$player})) {
					# We have a new player
					warn "Error: somehow a new player snuck in...";
					$need_rcon_poll = 1;
				}
			}
		}
	}

	# Check the list of 'connecting' players to see if they are still listed as trying to connect, if not then delete them from the list.
	foreach my $player (keys %connecting_players) {
		if ( !exists($secondary_player_hash{$player}) ) {
			warn "Somebody briefly connected to the the server,\n But left before we could get their info.";
			warn "Name was: $player \n";
			delete $connecting_players{$player};
		}
	}

	# II.) Now that the new list has been processed, update the player stats...

	foreach my $player (keys %secondary_player_hash) {
		# Only update the information if we have an entry in the main hash for them.
		if ( exists($main_player_hash{$player}) ) {
			# Update each player's stats.
			my $ping	= $secondary_player_hash{$player}->{ping};
			my $score	= $secondary_player_hash{$player}->{score};
			
			$main_player_hash{$player}->{ping}	= $ping;			# store the ping
			$main_player_hash{$player}->{score}	= $score;			# store the score
			
			# A ping of "999" means that a player 'timed-out' and is not a valid ping
			if ($ping != 999) {
				# Update the player's ping stats
				if ( exists($main_player_hash{$player}->{max_ping}) ) {
					if ($ping > $main_player_hash{$player}->{max_ping}) {
						$main_player_hash{$player}->{max_ping}	= $ping;}
					elsif ($ping < $main_player_hash{$player}->{min_ping}) {
						$main_player_hash{$player}->{min_ping}	= $ping; }
				} else {
					$main_player_hash{$player}->{max_ping}	= $ping;
					$main_player_hash{$player}->{min_ping}	= $ping;
				}
			}
			
			# Update the players score stats
			if ( exists($main_player_hash{$player}->{max_score}) ) {
				if ($score > $main_player_hash{$player}->{max_score}) {
					$main_player_hash{$player}->{max_score}	= $score;}
				elsif ($score < $main_player_hash{$player}->{min_score}) {
					$main_player_hash{$player}->{min_score}	= $score; }
			} else {
				$main_player_hash{$player}->{max_score}	= $score;
				$main_player_hash{$player}->{min_score}	= $score;
			}
		}
	}

	# III.) Finally, check if anybody has gone missing from the old list...

	my $dur = 0;
	foreach my $old (keys %main_player_hash) {
		if ( !exists($secondary_player_hash{$old}) ) {
			# Somebody disconnected
			$dur = ($time - $main_player_hash{$old}->{time});	# Calculate how long they were on the server
			
			print "Name: ". $old . "\tDisconnected.\n";
			print " connected at: ". $main_player_hash{$old}->{time} . "\n";
			print " duration: ". $dur ." seconds\n";
			
			warn Dumper $main_player_hash{$old};

			# Update the player table with their new duration
			$dbhandle->do('UPDATE `players` SET duration='.($main_player_hash{$old}->{duration} + $dur).' WHERE player_id='. $main_player_hash{$old}->{player_id})
			or die("Unable to execute query.\n". $dbhandle->errstr ."\n");
			
			# Add an entry to the 'rcon_log' table
			$dbhandle->do('INSERT INTO `rcon_log` (datetime,player_id,ip,slot,action) VALUES (FROM_UNIXTIME('. $time .'),'.$main_player_hash{$old}->{player_id}.',INET_ATON("'. $main_player_hash{$old}->{ip} .'"),'.$main_player_hash{$old}->{slot}.',0)')
			or die("Unable to execute query.\n". $dbhandle->errstr ."\n");
			
			delete $main_player_hash{$old};
		}
	}
}

# Checks the 'error number' passed to it and returns a string describing the error.
sub error_msg($) {
	my $err = shift;
	
	# if ( nondigit OR positive )
	if ( $err !~ /^-?\+?\d+$/o || int($err) > 0 ) {
		return undef; }
	
	if ( !exists($errors{$err}) ) {
		warn '--- An Unknown Error Number Occured ---';
		return undef;
	} else {
		return $errors{$err};
	}
}

sub urt_serverError($) {
	#--- A Problem Occured Getting Server Information ---
	my $result = shift;

	if ($result =~ m/\nBad rconpassword.\n/o) {
		$result = -10;
	} elsif ($result =~ m/\nbroadcast: print "status"/o) {
		$result = -11;
	}
		
	if ( exists($errors{ int($result) }) ) {
		$backend_status = int($result);
		
		# If a timeout occured, then store the time at which it approximately occured. Also increment the timeout counter
		if ($backend_status == -5) { $timeout_last = time(); $timeouts++; }
		# Request rcon poll next time.
		$need_rcon_poll = 1;
		
		warn error_msg($backend_status) ."\n";	# Output error message		
	} else {	# Catch all... 
		die("An unknown error occured...\nThe server's response was unrecognized."); }
}

# Update the "status" database with our current information.
sub db_updateStatus() {
	$last_update = time();	# Grab the current time.
	$dbhandle->do('UPDATE `status` SET backend_status='.$backend_status.',log_lines_processed='.$log_lines_processed.',log_bytes_processed='.$log_bytes_processed.',log_last_check='.$log_last_check.',last_update='.$last_update);
}

# This function is called after an rcon update and the svars have changed
sub db_updateServer() {
	my $qry = '';
	my $map = '';
	my $map_safe = '';
	my $srv_name = '';
	my $svars = '';
	
	if ($urt_svars) {
		$svars = $dbhandle->quote($urt_svars);
		
		my @svars = split(/\\/o, $urt_svars);	# bust up the server variables string
		my %s_vars = @svars[1..$#svars];		# now store a hash of the game options
	
		if (!exists($s_vars{'mapname'}) || !exists($s_vars{'sv_hostname'})) {
			warn "Error: Something is wrong with the server svars...";
		} else {
			$map		= $s_vars{'mapname'};
			$map_safe	= $dbhandle->quote( $map );
			$srv_name	= $dbhandle->quote( $s_vars{'sv_hostname'} );
		}
		
		$qry = 'UPDATE `servers` SET timeouts='.$timeouts.',timeout_last='.$timeout_last.',name='.$srv_name.',current_map='.$map_safe.',svars='.$svars.' WHERE server_id='. $server_id;
	} else {
		$qry = 'UPDATE `servers` SET timeouts='.$timeouts.',timeout_last='.$timeout_last.' WHERE server_id='. $server_id;
	}	

	$dbhandle->do($qry) or die('Could not update database with server information...');


	# If a new map is seen, add to the hash, and update the [map] table
	if (($map) && !exists( $map_list_hash{$map} )) {
		$map_list_hash{$map} = 1;
		db_updateMapList();
	}


	# TODO: Update the database [gametype] table(s) with info from new svars
}

sub db_updateMapList() {
	if ((keys %map_list_hash) > 1) {
		my $name	= '';
		my $qry		= '';
		my $times	= 0;
		my $rows	= 0;

		foreach my $map (keys %map_list_hash) {
			# TODO: unpack a string from the maplist hash that also has the 'duration'

			$name = $dbhandle->quote($map);
			$times = int($map_list_hash{$map});
			$qry = 'UPDATE `maps` SET times_played='. $times .' WHERE map_name='. $name;

			$rows = $dbhandle->do($qry) or die('Error updating database map list...');

			if (!defined($rows) || $rows == -1) {
				print 'An error occured while updating the database map list...';
			} elsif ($rows == 0) {
				$qry = 'INSERT INTO `maps` (map_name, times_played) VALUES ('. $name .', '. $times .')';

				$rows = $dbhandle->do($qry) or die('Error updating database map list...');
				if ($rows != 1) {
					print 'An error occured while inserting a new map into the maplist..';
				}
			}
		}

	} else {
		print "Error: No maps currently stored in the map hash.\n";
	}
}

# We sleep a different amount depending on what is going on...
sub conditional_sleep() {
	if ($backend_status == -5) {
		print "Timeout occured, sleeping for $timeout_wait_delay seconds\n";
		sleep($timeout_wait_delay);
	} elsif ($backend_status == -12) {
		print "rcon password not set yet, sleeping for 10 seconds\n";
		sleep(10);		# No rcon pw, sleep for awhile
	} elsif ($backend_status == -13) {
		print "Waiting for server config, sleeping for 20 seconds\n";
		sleep(20);
	} elsif ($backend_status == -10 ) {
		print "Bad rcon password, sleeping for 30 seconds\n";
		sleep(30);
	} elsif ($backend_status == 10) {	# client request to 'pause' the backend
		print "(Paused)\n";
		sleep(30);
	} elsif ($backend_status < 0) {
		print "An error occured. sleeping for 15 seconds.\n";
		sleep(15);
	} elsif ($need_rcon_poll == 0) {
		sleep(3)		# Default sleep time
	} else {
		sleep(1);		# Between getStatus and rconStatus
	}
}

##### End of Subroutines #####


#============================================
#	Main Loop
#============================================

db_getStatus();
db_getServerInfo();
db_getMapList();

if ($backend_status < 0) {
	print "Looks like there was a problem last time.\nThe error was:\n";
	print "\t". error_msg($backend_status). "\n\n"; }

$backend_status = 1;

# main()

while ($main_status) {
	db_getStatus();

	# Handle any 'client_request'
	if ($client_request == -1) {
	
		dump_debug();
		
	} elsif ($client_request == -100) {		# Terminate program
	
		$dbhandle->disconnect();
		die('--> Got signal from client: Shutting down...');
	
	} elsif ($client_request == 10) {		# Pauses backend from polling server

			warn "--> Got request to pause.\n";
			$backend_status = 10;

	} else {	# If no recognized client requests, then poll the server as per usual.

		if ($urt_server) {				# Have a server IP address...
			if ($need_rcon_poll > 0) {		# Then query the server...
				if (!$urt_rcon_pw) {
					$backend_status = -12;
					warn error_msg($backend_status);
				} else {
					urt_rconStatus();
				}
			} else {
				urt_getStatus();
			}

			db_doPlayerStats();
			db_updateServer();
		}
	}

	db_updateStatus();

	conditional_sleep();
}
