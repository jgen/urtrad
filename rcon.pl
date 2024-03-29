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
$Data::Dumper::Indent = 1;		# Mild indentation

#use Time::HiRes qw/usleep/;

use POSIX qw/strftime/;			# Date/time Formatting
use Getopt::Long;			# Command-line Options
use Pod::Usage;				# Command-line Documentation
use Socket;				# Communicating with ioUrbanTerror Server
use DBI;				# For database access
    
#require './urt_common.pl';		# Not currently used fully, maybe later on [useful for stats]


# ----- Command line Options -----
my $opt_verbose	= 0;			# Verbosity of output (0=limited, 1=normal, 2=detailed)
my $opt_log	= '';			# Log all output to a given file
my $opt_help	= 0;			# Output help and exit if set


# ----- Database Configuration -------
# Centralized config for database
# - shared between rcon.pl and interface.php
my %db;
my $db_config_file = 'db_config.php';


# ----- Urban Terror Sever Variables ------
# [ These are set via the database ]
my $urt_server		= 0;
my $urt_port		= 0;
my $urt_proto		= getprotobyname('udp');
my $urt_rcon_pw		= '';
my $urt_addr		= '';
my $urt_svars		= '';
my $urt_map		= '';

my $server_id			= 0;
my $timeouts			= 0;		# Number of timeouts that have occured
my $timeout_last		= '';		# Datetime string of the last timeout
my $timeout_delay		= 5;		# How long to wait for a packet
my $timeout_wait_delay		= 10;		# If a timeout occurs, how long to wait before trying again


# ----- Socket Configuration -----
my $socket_handle;
my $SOCK_MAX_LENGTH	= 1500;		# Ethernet MTU is 1500 bytes -- Absolute maximum is 65,535
my $SOCK_MAX_PACKETS	= 64;		# Maximum number of packets for a response
my $SOCK_TIMEOUT	= 1;		# Seconds to wait for Secondary response (additional packets)
my $SOCK_PACKET_SIZE	= 950;		# Approx. size of ioQuake3 packet after which messages are split


# ----- Polling Configuration -----
# Amount of time to wait between polling events (in seconds)

my $SLEEP__NO_RCON_PW		= 10;
my $SLEEP__NO_SERVER_CFG	= 20;
my $SLEEP__BAD_RCON_PW		= 30;
my $SLEEP__PAUSE_REQUEST	= 30;
my $SLEEP__UNKNOWN_ERROR	= 15;
my $SLEEP__DEFAULT 		=  3;
my $SLEEP__NEED_RCON_POLL	=  1;

# How long to wait for somebody to connect
# (Default is 3 minutes)
my $MAX_CONNECTION_TIME = int( 180 / $SLEEP__DEFAULT );


# ----- Status Table Vars -----
my $backend_status		= 0;
my $client_request		= 0;
my $log_lines_processed		= 0;		# not currently used
my $log_bytes_processed		= 0;		# not currently used
my $log_last_check		= 0;		# not currently used
my $log_check_delay		= 25;		# not currently used
my $last_update			= '';		# Datetime string of the last update


# ----- Global Status Vars -----
my $main_status			= 1;
my $need_rcon_poll		= 1;
my $just_rcon_polled		= 0;

my %main_player_hash		= ();
my %secondary_player_hash	= ();
my %connecting_players		= ();
my %map_list_hash		= ();


# ----- Program Stats -----
my %stats;
$stats{'total_packets'} = 0;
$stats{'total_bytes'} = 0;
$stats{'total_rcon'} = 0;
$stats{'total_getstatus'} = 0;


# ----- Error Messages -----
my %errors = (
	-1	=> 'Could not open a socket.',
	-2	=> 'Could not connect to external address.',
	-3	=> 'Could not send message to server.',
	-4	=> 'Error recieving data from server.',
	-5	=> 'Server did not respond - request timed out.',
	-6	=> 'Could not close the socket.',
	-7	=> 'The connection was refused',
	-10	=> 'Bad rcon password.',
	-11	=> 'The server did not recognize the command.',
	-12	=> 'No rcon password set yet.',
	-13	=> 'Server config is missing or incorrect.'
);
# -----------


############ Start of Execution #############


# Process command-line options
GetOptions(
	'h|help|?:+' => \$opt_help,
	'v|verbose:+' => \$opt_verbose,
	'log=s' => \$opt_log
) or pod2usage({-verbose => 1, -output => \*STDOUT}) && exit(2);

pod2usage({-verbose => $opt_help, -output => \*STDOUT}) && exit if ($opt_help);

# Setup logging if needed.
if ($opt_log) {
	# Redirect all output to a log file
	close(STDOUT);
	close(STDERR);

	open (STDOUT, '>>', $opt_log) or die "Can't open file '$opt_log' -- $!";
	open (STDERR, ">&STDOUT")     or die "Can't dup STDOUT: $!";

	select STDERR; $| = 1; # make unbuffered
	select STDOUT; $| = 1; # make unbuffered
}


#--- Read in the database config ---
# (Add an option to wait for the config...)

if ( !( -e $db_config_file ) || !( -r $db_config_file ) ) {
	die('The database config file is either missing, or unaccessable.'."\n\t".'(File: '.$db_config_file.")\n"); }
if (-z $db_config_file) {
	die('The database config file is empty [0 bytes].'."\n\t".'(File: '.$db_config_file.")\n"); }

if ((stat($db_config_file))[7] > 1024 ) {
	die ("The database config file is too large.\nI don't feel safe opening it. (size > 1 kB)\n"); }

my $dbconfig; # Read the entire file into $dbconfig
{
	local($/, *hndl);
	open(hndl, '<', $db_config_file) or die('Unable to open the file!');
	$dbconfig = <hndl>;
	close(hndl) or die('Unable to close the file!');
}

if ($dbconfig =~ m/%db\s*=\s*\(([^\);]*)\);/) {
	$dbconfig = $1;
} else {
	die("Error reading the database config file.\nCould not find the config section.\n");
}

if ($dbconfig =~ m/'driver'\s*=>\s*'([^']+)'/) {
	$db{'driver'} = $1;
} else {
	die('No database driver was specified in the database config file.');
}

# -- Check if we can connect to that type of database --
my %server_drivers = map {$_, 1} DBI->available_drivers();
if ( !exists $server_drivers{$db{'driver'}} ) {
	print 'No driver is currently installed for a "'. $db{'driver'} .'" database.'."\n";
	print 'Available drivers: ';
	$, = ', ';
	print keys %server_drivers;
	die("\n");
}

# If the database is SQLite, then we do not need host,port,username, & password.
if ($db{'driver'} !~ m/sqlite/io) {
	if ($dbconfig =~ m/'host'\s*=>\s*'([^']*)'/) {
		$db{'host'} = $1;

		if (!inet_aton($db{'host'})) {
			die ('Could not resolve database host "'. $db{'host'} .'".'."\n");
		}
	} else {
		die('No database host was specified in the database config file.');
	}

	if ($dbconfig =~ m/'port'\s*=>\s*'([^']*)'/) {
		$db{'port'} = int($1);

		if (int($db{'port'}) > 65535 || int($db{'port'}) < 0) {
			die ('Invalid port ['. $db{'port'} .'] specified for database server.'."\n");
		}
	} else {
		die('No port number was specified in the database config file.');
	}

	if ($dbconfig =~ m/'user'\s*=>\s*'([^']*)'/) {
		$db{'user'} = $1;

		if (!length($db{'user'})) {
			die ('No user name was specified in the database config file.');
		}
	} else {
		die ('No username was specified in the database config file.');
	}

	if ($dbconfig =~ m/'pass'\s*=>\s*'([^']*)'/) {
		$db{'pass'} = $1;

		if (!length($db{'pass'})) {
			print 'Using an empty password. Consider setting a password for more security.'."\n";
		}
	} else {
		$db{'pass'} = '';
		print 'No password was specified in the database config file. Consider setting one.';
	}
}

if ($dbconfig =~ m/'database'\s*=>\s*'([^']*)'/) {
	$db{'database'} = $1;
	if (!length($db{'database'})) {
		die ('No database specified for the program to use.');
	}
	# If the database is SQLite, then check if the database file is accessable...
	if ($db{'driver'} =~ m/sqlite/io) {
		if ( !( -e $db{'database'} ) || !( -r $db{'database'} ) ) {
			die('The SQLite database file is either missing, or unaccessable.'."\n\t".'Filename Specified in Config: '.$db{'database'}."\n");
		}
		if (-z $db{'database'}) {
			die('The SQLite database file is empty [0 bytes].'."\n\t".'Filename Specified in Config: '.$db{'database'}."\n");
		}
	}
} else {
	die('No database name (schema) was specified in the database config file.');
}


# ---- Setup global database connector variables ----
my $dsn = '';
if ($db{'driver'} =~ m/sqlite/io) {
	$dsn = 'dbi:SQLite:dbname='.$db{'database'};
} else {
	$dsn = 'dbi:'.$db{'driver'}.':database='.$db{'database'}.';host='.$db{'host'}.';port='.$db{'port'}.';';
}
my $dbhandle = DBI->connect($dsn, $db{'user'}, $db{'pass'}) 
	or die("Unable to connect to the database.\n". DBI->errstr ."\n");


# Called on program termination
END {
	if (defined $dbhandle) {
		if ($dbhandle) {
			if ($dbhandle->err()) {
				print 'Error '.$dbhandle->err().': '. $dbhandle->errstr ."\n"; }
			if ($opt_verbose) { print "Disconnecting from database...\n"; }

			$dbhandle->disconnect();
		}

		if ($socket_handle) { close $socket_handle; }

		if ($opt_verbose > 1) {
			dump_debug();
		}

		print localtime(time())." < Program Terminated >\n";
	}
}
#----------------


######### Subroutines #########

# Dump debug information to stdout/log file.
sub dump_debug() {
	my $indent = $Data::Dumper::Indent; # save current indent level

	print '-' x 40 . "\n";
	print '['. localtime(time()) ."]\n";
	print '-->  Dumping Debug Information:'."\n";
	
	print '     main_status = '. $main_status . "\n";
	print '  need_rcon_poll = '. $need_rcon_poll . "\n";
	print 'just_rcon_polled = '. $just_rcon_polled . "\n";

	$Data::Dumper::Indent = 2; # indent output

	print Data::Dumper->Dump( [\%stats], [qw(*stats)] );
	print Data::Dumper->Dump( [\%main_player_hash], [qw(*main_player_hash)] );
	print Data::Dumper->Dump( [\%secondary_player_hash], [qw(*secondary_player_hash)] );
	print Data::Dumper->Dump( [\%connecting_players], [qw(*connecting_players)] );
	print Data::Dumper->Dump( [\%map_list_hash], [qw(*map_list_hash)] );
	print '-' x 40 . "\n";

	$Data::Dumper::Indent = $indent; # restore indent level
}

sub db_getStatus() {
	my $status_query = 'SELECT * FROM `status`';
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
		$last_update = $dbhandle->quote( strftime('%F %T', localtime(time()) ) );	# datetime string: 'YYYY-MM-DD HH:MM:SS'
		
		$dbhandle->do('INSERT INTO `status` (backend_status,client_request,log_lines_processed,log_bytes_processed,log_last_check,last_update) VALUES ('."$backend_status, $client_request, $log_lines_processed, $log_bytes_processed, $log_last_check, $last_update )")
			or die('Unable to execute query.');
	} else {
		# Set the Global Status Variables
		$backend_status		= int(${$status}{'backend_status'}) || 0;
		$client_request 	= int(${$status}{'client_request'}) || 0;
		$log_lines_processed	= int(${$status}{'log_lines_processed'}) || 0;
		$log_bytes_processed	= int(${$status}{'log_bytes_processed'}) || 0;
		$log_last_check		= int(${$status}{'log_last_check'}) || 0;
		#$log_check_delay	= int(${$status}{'log_check_delay'});
		$last_update		= ${$status}{'last_update'};
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
		$urt_server		= inet_aton( ${$servers}{'ip'} );
		$urt_port		= int(${$servers}{'port'}) || 27960;
		$urt_rcon_pw		= ${$servers}{'rcon_pw'};
		$urt_addr		= sockaddr_in($urt_port, $urt_server);
		
		$server_id		= int(${$servers}{'server_id'});
		$timeouts		= int(${$servers}{'timeouts'}) || 0;
		$timeout_delay		= int(${$servers}{'timeout_delay'}) || 5;
		$timeout_last		= ${$servers}{'timeout_last'};
		$timeout_wait_delay	= int(${$servers}{'timeout_wait_delay'}) || 10;
	}
	$servers_query_hndl->finish();
}

# Get the list of maps from the database and store them in the map_list hash.
sub db_getMapList() {
	my $map_qry = 'SELECT * FROM `maps`';
	my $map_qry_hndl = $dbhandle->prepare($map_qry) or die("Unable to prepare query.\n". $dbhandle->errstr ."\n");
	$map_qry_hndl->execute() or die("Unable to execute query.\n". $map_qry_hndl->errstr ."\n");

	my $rows = $map_qry_hndl->rows();
	my $map_row;

	if (!defined($rows) || $rows < 1) {
		# no maps in the database map listing.
		if ($opt_verbose) {
				print "No maps were found in the database. (Perhaps this is the first time running?).\n";
		}

		# Query the server to get a full listing of maps files on the sever
		urt_getMapList();
	} else {
		while ( $map_row = $map_qry_hndl->fetchrow_arrayref ) {
			# make an entry in the map list hash
			if (scalar(@{$map_row}) > 3) {
				$map_list_hash{$map_row->[1]} = $map_row->[2];
			} else {
				if ($map_row->[1] && $map_row->[2] eq '') {
					print "There is a map in the database with no name,\n  Deleteing all maps entries with no name...\n";
					$dbhandle->do('DELETE FROM `maps` WHERE `map_name`=""') or die("Unable to execute query.\n". $dbhandle->errstr ."\n");
				} else {
					print "There is a problem with the map table in the database.\n";
					if ($opt_verbose > 1) {
						print 'Total rows in `maps`: '. $rows ."\nRow that caused a problem dumped below:\n";
						print Data::Dumper->Dump( [\$map_row], [qw(*map_row)] );
					}
				}
			}
		}
	}
	$map_qry_hndl->finish();
}

sub urt_rconStatus() {
	print '['.localtime(time)."] Requesting rcon status update.\n";

	my $msg = chr(255) x 4 . 'rcon '. $urt_rcon_pw .' status'.chr(12);
	my $result = urt_queryServer($msg, $urt_addr, $socket_handle);

	if ( length($result) < 29 ){
		urt_serverError($result);
	} else {	#-------------------- Got Sever Response --------------------
		$backend_status	= 1;
		$just_rcon_polled = 1;
		$need_rcon_poll	= 0;
		$stats{'total_rcon'} += 1;	# successful rcon replies
	
		# Remove the old list of players from the database.
		$dbhandle->do('DELETE FROM `current_players`') or die('Unable to execute query.');
		
		# Only delete the players from the list that were actually _connected_ (ie: they had a slot number)
		foreach (keys %secondary_player_hash) {
			if (exists($secondary_player_hash{$_}->{'slot'})){
				delete $secondary_player_hash{$_};
			}
		}
		
		$result =~ s/\xFF\xFF\xFF\xFFprint\n//go;	# Clean up the server response
		
		my @reply = split(/\n/o, $result);
		my @pvars;
		
		if (@reply > 3) {	# Check if there are any players on the server
			my $tmp_str = '';
			my $name = '';
			my $ip = 0;
		
			foreach( @reply[3..$#reply] ) {
		
				if ($_ =~ m/^ *(\d+) +(-{0,1}\d+) +(\d+) +(.+?)\^7 +(\d+) ([\d\.]+):(\d+) +(\d+) +(\d+)$/o) {
					@pvars = (0,$1,$2,$3,$4,$5,$6,$7,$8,$9);
					
					$name = $4;
					$name =~ s/^\s+|\s+$//o;	# Trim leading and trailing whitespace
				
					# This is pretty much a hack to cover players with no name (null length string)
					if ($name eq '') {
						$name = ';NULL';
						if ($opt_verbose > 1) { warn 'Warning, a player with no name has connected.'; }
					}

					$ip = unpack('N', inet_aton( $pvars[6] ) );	# Convert the IP string to an integer
					
					$secondary_player_hash{$name} ={slot	=> $pvars[1],
									score	=> $pvars[2],
									ping	=> $pvars[3],
									ip	=> $pvars[6],
									qport	=> $pvars[8],
									rate	=> $pvars[9] };

					# Multiple inserts are unfortunately necessary as not all databases support multiline inserts (ie: SQLite).
					$tmp_str = '('.$pvars[1].','.$pvars[2].','.$pvars[3].','.$dbhandle->quote($name).','.$ip.','.$pvars[8].','.$pvars[9].')';

					$dbhandle->do('INSERT INTO `current_players` (slot_num,score,ping,name,ip,qport,rate) VALUES '. $tmp_str)
						or die("Unable to execute query.\n\n$tmp_str");
				}
			}
		} else {
			if ($opt_verbose) { print "No players connected to the server\n"; }
		}
	}
}

sub urt_getStatus() {
	my $msg = chr(255) x 4 . 'getstatus'. chr(12);
	my $result = urt_queryServer($msg, $urt_addr, $socket_handle);

	if ( length($result) < 29 ){
		urt_serverError($result);
	} else {	#-------------------- Got Sever Response --------------------
		$stats{'total_getstatus'} += 1;	# successful getstatus repliess
		my @reply = split(/\n/o, $result);
		
		if ($reply[1] ne $urt_svars ) {		# if the server config vars have changed
			if ($just_rcon_polled) {
				$urt_svars = $reply[1];		# update the svar string
				db_updateServer();		# update the server info in the database
			} else {
				if ($opt_verbose) { print "--> Server svars have changed.\n"; }
				$need_rcon_poll = 1;
				#return;		# We don't need to return right away...
			}
		}
		$just_rcon_polled = 0;
		
		# Temporary variables
		my $name = '';
		my $ping = 0;
		my $score = 0;
		my @players = @reply[2..$#reply];		# store the players in a new array

		if (scalar(@players) != (scalar(keys %secondary_player_hash) + scalar(keys %connecting_players))) {
			# We have a different number of players compared to last time
			if ($opt_verbose) {
				print '['.localtime(time).'] Number of players changed.';
				if ($opt_verbose > 1) {
					print '    [p:'.scalar(@players).' s:'.scalar(keys %secondary_player_hash).' c:'.scalar(keys %connecting_players).']';
				}
				print "\n";
			}
			$need_rcon_poll = 1;
		}
		
		foreach ( @players ) {
			$_ =~ m/^(-{0,1}\d+) (\d+) "([^\"]*)"$/o;
			
			$score	= $1;
			$ping	= $2;
			$name	= $3;
			$name	=~ s/^\s+|\s+$//o;	# Trim leading and trailing whitespace

			# This is pretty much a hack to cover players with no name (null length string)
			if ($name eq '') {
				$name = ';NULL';
				if ($opt_verbose > 1) { warn 'Warning, a player with no name has connected.'; }
			}
			
			if ( !exists($secondary_player_hash{$name}) && !exists($connecting_players{$name}) ) {
				if ($opt_verbose > 1) {
					print ' Name detected: '. $name ."\n";
				}
				$need_rcon_poll = 1;	# new player name found: request rcon update
			}
			# If this player was 'connecting' last time but has a valid ping now, remove them from 'connecting' hash and request rcon update.
			if ( exists($connecting_players{$name}) && $ping != 999 ) {
				delete $connecting_players{$name};
				$need_rcon_poll = 1;
			}

			# Update the list of players with the new information...
			$secondary_player_hash{$name}->{'score'}	= $score;
			$secondary_player_hash{$name}->{'ping'}	= $ping;
			$name = $dbhandle->quote($name);
			
			$dbhandle->do('UPDATE `current_players` SET score='.$score.',ping='.$ping.' WHERE name='. $name);
		}
	}
}

# Retrieve the full map listing from the server.
sub urt_getMapList() {
	print '['.localtime(time)."] Requesting full map list from server....\n";

	my $msg = chr(255) x 4 . 'rcon '. $urt_rcon_pw .' fdir *.bsp'. chr(12);
	my $result = urt_queryServer($msg, $urt_addr, $socket_handle);

	if ( length($result) < 29 ){
		urt_serverError($result);
	} else {	#--------------- Got Sever Response ---------------
		my @reply = split(/\n/o, $result);
		
		if (@reply < 3) {
			print 'Error: It looks like there are no maps on the server.';
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

# Called when the same IP and slot has a different name.
sub changeName($$$$) {
	my $old		= shift || undef;	# Old player name
	my $new		= shift || undef;	# New player name
	my $time	= shift || time;
	my $dtime	= shift || $dbhandle->quote( strftime('%F %T', localtime($time)) );	# datetime string: 'YYYY-MM-DD HH:MM:SS'
	
	if (!$old || !$new) {
		warn 'Error: A Null player name was passed to changeName() ';
		return; }
	
	my $ip		= unpack('N', inet_aton( $main_player_hash{$old}->{'ip'} ) );	# Convert the IP string to an integer
	my $name	= $dbhandle->quote($new);					# Escape the new name

	# Check if we have seen that Name before
	my $name_qry = 'SELECT * FROM `players` WHERE name='. $name;
	my $name_qry_hndl = $dbhandle->prepare($name_qry) or die("Unable to prepare query.\n". $dbhandle->errstr ."\n");
	$name_qry_hndl->execute() or die("Unable to execute query.\n". $name_qry_hndl->errstr ."\n");
	my $name_results = $name_qry_hndl->fetchrow_arrayref();
	
	# Name Check
	if ($name_qry_hndl->rows > 1) {
		# Name listed in the players table more then once... this should _Not happen_ if the database is setup correctly
		warn '-> Duplicate Name entries in `players` table... ';
		return;
	} elsif ($name_qry_hndl->rows == 1) {
		# Name is listed in the players table
		$main_player_hash{$old}->{'player_id'}	= @{$name_results}[0];	# Store the new player_id
		$main_player_hash{$old}->{'duration'}	= @{$name_results}[2];	# Store the new player duration
	} else {
		# We have not seen this name before...
		print "New player name, adding to database...\n";
		# Create a new entry in the players table
		$dbhandle->do('INSERT INTO `players` VALUES (NULL,'.$name.', 0,'. $dtime .')')
		or die("Unable to execute query.\n". $dbhandle->errstr ."\n");

		my $name_qry2 = 'SELECT * FROM `players` WHERE name='. $name;
		my $name_qry2_hndl = $dbhandle->prepare($name_qry2) or die("Unable to prepare query.\n". $dbhandle->errstr ."\n");
		$name_qry2_hndl->execute() or die("Unable to execute query.\n". $name_qry2_hndl->errstr ."\n");
		my $name_results2 = $name_qry2_hndl->fetchrow_arrayref();
		
		$main_player_hash{$old}->{'player_id'}	= @{$name_results2}[0];	# Store the player_id
		$main_player_hash{$old}->{'duration'}	= 0;			# Zero the duration as its a new name;
		$name_qry2_hndl->finish();
	}
	$name_qry_hndl->finish();

	# Store the Player ID
	my $player_id = $main_player_hash{$old}->{'player_id'};

	# IP Check
	my $ips_qry = 'SELECT * FROM `ips` WHERE player_id='. $player_id .' AND ip='. $ip;
	my $ips_qry_hndl = $dbhandle->prepare($ips_qry) or die("Unable to prepare query.\n". $dbhandle->errstr ."\n");
	$ips_qry_hndl->execute() or die("Unable to execute query.\n". $ips_qry_hndl->errstr . "\n");
	my $ips_results = $ips_qry_hndl->fetchrow_arrayref();

	if ($ips_qry_hndl->rows > 1) {
		warn '-> Duplicate entries in the `ips` table... ';
		return;
	} elsif ($ips_qry_hndl->rows == 1) {
		# Player has been seen with this ip before
		# - nothing really to do..
	} else {
		# New ip for this player name
		$dbhandle->do('INSERT INTO `ips` VALUES ('.$ip.',"'. $main_player_hash{$old}->{'ip'} .'",'.$player_id.','.$dtime.')')
			or die("Unable to execute query.\n". $dbhandle->errstr ."\n");
	}
	$ips_qry_hndl->finish();
}

# Called when a new player name is detected.
sub newPlayer($$$) {
	# Check the database for existing entries that match the IP / Name and update them Or create new entries.
	# Also: Add a new player to the main_player_hash
	my $player	= shift;			# player name
	my $time	= shift || time();		# the time we detected them
	my $dtime	= shift || $dbhandle->quote( strftime('%F %T', localtime($time)) );	# datetime string: 'YYYY-MM-DD HH:MM:SS'
	
	if (!$player) {
		warn 'Error: A Null player name was passed to newPlayer()';
		return;	}
	
	my $ip = unpack('N', inet_aton( $secondary_player_hash{$player}->{'ip'} ) );	# Convert the IP string to an integer
	
	if (!$ip) {
		warn 'Error: The player passed to newPlayer() does not have an IP address.';
		return; }

	my $name	= $dbhandle->quote($player);	# escape the name for safe database useage
	my $playerid	= 0;				# pulled in from the database
	my $duration	= 0;				# duration's default value is zero

	printf("> Checking IP:%15s\tName: %-20s\n", $secondary_player_hash{$player}->{ip}, $player);
	
	# Check if we have seen that Name before
	my $name_qry = 'SELECT * FROM `players` WHERE name='. $name;
	my $name_qry_hndl = $dbhandle->prepare($name_qry) or die("Unable to prepare query.\n". $dbhandle->errstr ."\n");
	$name_qry_hndl->execute() or die("Unable to execute query.\n". $name_qry_hndl->errstr ."\n");
	my $name_results = $name_qry_hndl->fetchrow_arrayref();
	
	# Name Check
	if ($name_qry_hndl->rows > 1) {
		# Name listed in the players table more then once... this should _Not happen_ if the database is setup correctly
		warn '-> Duplicate Name entries in `players` table...';
		return;
	} elsif ($name_qry_hndl->rows == 1) {
		# Found player name in the table
		$playerid = @{$name_results}[0];
		$duration = @{$name_results}[2];
	} else {
		# We have not seen this name before...
		print '> New name, adding to database...'."\n";
		# Create a new entry in the players table
		$dbhandle->do('INSERT INTO `players` VALUES (NULL,'.$name.',0,'.$dtime.')')
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
	$secondary_player_hash{$player}->{'player_id'}	= $playerid;
	$secondary_player_hash{$player}->{'duration'}	= $duration;
	$secondary_player_hash{$player}->{'time'}	= $time;	# time player was detected


	# Check if we have seen that IP before
	my $ip_qry = 'SELECT * FROM `ips` WHERE ip='. $ip .' AND player_id='. $secondary_player_hash{$player}->{'player_id'};
	my $ip_qry_hndl = $dbhandle->prepare($ip_qry) or die("Unable to prepare query.\n". $dbhandle->errstr ."\n");
	$ip_qry_hndl->execute() or die("Unable to execute query.\n". $ip_qry_hndl->errstr ."\n");
	my $ip_results = $ip_qry_hndl->fetchrow_arrayref();

	# IP Address Check
	if ($ip_qry_hndl->rows > 1) {
		# IP AND Player_ID is listed more then once... this should _Not happen_ if the database is setup correctly
		warn '-> Duplicate IP entries in `ips` table... ';
		return;
	} elsif ($ip_qry_hndl->rows == 1) {
		# The IP AND Player_ID are listed in the table
		# - we have seen this IP with this Name before.
		if ($opt_verbose) { print '> Welcome back: '. $player ."\n"; }
	} else {
		# We have not seen that IP AND player name together before...
		# Create a new entry in the ips table
		$dbhandle->do('INSERT INTO `ips` VALUES ('.$ip.',"'.$secondary_player_hash{$player}->{'ip'}.'",'.$secondary_player_hash{$player}->{'player_id'}.','.$dtime.')')
			or die("Unable to execute query.\n". $dbhandle->errstr ."\n");
	}
	$ip_qry_hndl->finish();

	
	# Add an entry to the 'rcon_log' table
	$dbhandle->do('INSERT INTO `rcon_log` VALUES (NULL,'.$dtime.','.$secondary_player_hash{$player}->{'player_id'}.','. $ip .','.$secondary_player_hash{$player}->{'slot'}.',1)')
		or die("Unable to execute query.\n". $dbhandle->errstr ."\n");


	# Now that all the database stuff is taken care of, copy over the information on the player into the main players hash
	$main_player_hash{$player} = {};		# Make a key for them...
	
	foreach (keys %{$secondary_player_hash{$player}} )		# ...and load it with all the information we have on them.
		{ $main_player_hash{$player}->{$_} = $secondary_player_hash{$player}->{$_}; }
	
	# Remove them from the list of 'connecting players' [if they are in that list] since they have now fully connected to the server.
	if (exists($connecting_players{$player})) {
		delete $connecting_players{$player}; }
}

# Main function that handles player joins, disconnects, stats, etc.
sub db_doPlayerStats() {
	my $time = time();		# Store the current time ( for creating database entries and disconnects )
	my $dtime = $dbhandle->quote( strftime('%F %T', localtime($time)) );	# datetime string: 'YYYY-MM-DD HH:MM:SS'

	if ($main_status == 1) {		# On script startup we add all the players found on the server.
		foreach my $player (keys %secondary_player_hash) {
			newPlayer($player, $time, $dtime); }
		$main_status = 2;
		return;						# and thats it - there isn't much else to do.
	}

	# I.) First we process the new list of players...

	# Last update was a rcon status()
	if ($just_rcon_polled > 0) {

		foreach my $player (keys %secondary_player_hash) {
		
			if ((keys %{$secondary_player_hash{$player}}) < 3) {
				# This player is still "Connecting..." and is not listed in rcon status yet.
				if ($opt_verbose) {	print '~> Player: '.$player." is connecting...\n"; }
				# I suppose we could add the name to the players table. but we would have no IP to go with it....
				# So we store the name in a temporary hash of 'connecting players'
				# And check if they are fully connected next time, or have disappeared/disconnected.
				$connecting_players{$player} = 1;
				next; }
				
			if ( !exists($main_player_hash{$player}) ) {
				
				if (scalar( keys %main_player_hash ) == 0) {
					# New player joined empty server
					if ($opt_verbose) {	print "A player has joined an empty server.\n"; }
					newPlayer($player, $time, $dtime);
				} else {
					foreach my $old (keys %main_player_hash) {
						if ( ($main_player_hash{$old}{'ip'} eq $secondary_player_hash{$player}{'ip'}) && ($main_player_hash{$old}{'slot'} == $secondary_player_hash{$player}{'slot'}) ) {
							# If the ip AND the slot are the same
							# then it's the same player - they just changed their name
							if ($opt_verbose) {	print 'Player: '.$old.' changed name to '.$player."\n"; }
							changeName($old, $player, $time, $dtime);

							$main_player_hash{$player} = {};	# Make a new key for their new name.
							# Copy over their old data
							foreach (keys %{$main_player_hash{$old}})
									{ $main_player_hash{$player}->{$_} = $main_player_hash{$old}->{$_}; }
							delete $main_player_hash{$old};		# Delete the old key with their old name.
						}
					}
					# if they still don't exist in the old list, then they truly are a new player
					if ( !exists($main_player_hash{$player}) ) {
						if ($opt_verbose) {	print "+- A player has joined.\n"; }
						newPlayer($player, $time, $dtime);
					}
				}
			} else {
				if (!exists($main_player_hash{$player}{'ip'})) {
					# There is already an entry in the main hash for this player, but no ip.
					# We have an ip now, so let's add the player again to the main hash.
					newPlayer($player, $time, $dtime);
				} else {
					if (($main_player_hash{$player}->{'ip'} ne $secondary_player_hash{$player}->{'ip'}) || ($main_player_hash{$player}->{'slot'} ne $secondary_player_hash{$player}->{'slot'})) {
						# If the ip OR the slot are different but the name is the same
						# then we missed a disconnect AND a join.
						# --> This can happen frequently if timeouts are occuring.
						#
						print "Error: New player detected with previously used name.\nWe have missed a player Disconnect And a player Join\n";
						#print "Perhaps the time between status updates is too long?...\n";

						if ($main_player_hash{$player}->{'ip'} ne $secondary_player_hash{$player}->{'ip'}) {
							print 'Player "'. $player .'" has changed IPs. '.$main_player_hash{$player}->{'ip'}.' -> '.$secondary_player_hash{$player}->{'ip'}."\n";
						} else {
							print 'Player "'. $player .'" has changed slots. '.$main_player_hash{$player}->{'slot'}.' -> '.$secondary_player_hash{$player}->{'slot'}."\n";
						}

						if ($opt_verbose > 1) {
							warn 'Debug information: ';
							print 'Player Name = ' . $player ."\n";
							print Data::Dumper->Dump( [$main_player_hash{$player}], ['$main_player_hash{'.$player.'}'] );
							print Data::Dumper->Dump( [$secondary_player_hash{$player}], ['$secondary_player_hash{'.$player.'}'] );
						}
						# Is this really what should be done? remove the player?
						#  Perhaps we can adjust their info and carry on...
						print "Removing '".$player."' from both hashes.\n";
						delete $main_player_hash{$player};
						delete $secondary_player_hash{$player};
					}
				}
			}
		}
		foreach my $player (keys %connecting_players) {
			delete $secondary_player_hash{$player};
		}
	} else {
		# Last update was just a getStatus()
		# Only check if next update is not going to be an rcon update.
		if ($need_rcon_poll == 0) {
			foreach my $player (keys %secondary_player_hash) {
				if ( !exists($main_player_hash{$player}) && !exists($connecting_players{$player})) {
					# We have a new player
					warn 'Error: somehow a new player snuck in...';
					$need_rcon_poll = 1;
				}
			}
		}

		# Check the list of 'connecting' players to see if they are still listed as trying to connect, if not then delete them from the list.
		foreach my $player (keys %connecting_players) {
			if ( !exists($secondary_player_hash{$player}) ) {
				if ($opt_verbose) {
					print "A player connected to the the server, but disconnected before we could get their info, or else they did not fully connect.\n";
					print '  Name was: '.$player."\n";
					if ($opt_verbose > 1) {
						print Data::Dumper->Dump( [$connecting_players{$player}], ['$connecting_players{'.$player.'}'] );
					}
				}
				delete $connecting_players{$player};
			} else {
				if ($secondary_player_hash{$player}->{'ping'} != 999) {
					warn 'This should not happen and this should have been caught by now.';
					delete $connecting_players{$player};
					$need_rcon_poll = 1;
				} else {
					if ($opt_verbose > 1) { print 'Player '.$player.' is still connecting.'."\n"; }

					# Increment connection counter.
					$connecting_players{$player} += 1;

					# Remove them from the list of real players
					delete $secondary_player_hash{$player};

					# After set amount of 'connections' remove them from the list of connecting players
					# to prevent them sitting in the connecting_players hash forever...
					if ($connecting_players{$player} > $MAX_CONNECTION_TIME) {
						if ($opt_verbose) { print "Player $player has been 'connecting' too long.\nRemoving them from the connecting hash.\n"; }
						delete $connecting_players{$player};
					}
				}
			}
		}
	}

	# II.) Now that the new list has been processed, update the player stats...

	foreach my $player (keys %secondary_player_hash) {
		# Only update the information if we have an entry in the main hash for them.
		if ( exists($main_player_hash{$player}) ) {
			# Update each player's stats.
			my $ping	= $secondary_player_hash{$player}->{'ping'};
			my $score	= $secondary_player_hash{$player}->{'score'};
			
			$main_player_hash{$player}->{'ping'}	= $ping;			# store the ping
			$main_player_hash{$player}->{'score'}	= $score;			# store the score
			
			# A ping of "999" means that a player 'timed-out' and is not a valid ping
			if ($ping != 999) {
				# Update the player's ping stats
				if ( exists($main_player_hash{$player}->{'max_ping'}) ) {
					if ($ping > $main_player_hash{$player}->{'max_ping'}) {
						$main_player_hash{$player}->{'max_ping'} = $ping;}
					elsif ($ping < $main_player_hash{$player}->{'min_ping'}) {
						$main_player_hash{$player}->{'min_ping'} = $ping; }
				} else {
					$main_player_hash{$player}->{'max_ping'}	= $ping;
					$main_player_hash{$player}->{'min_ping'}	= $ping;
				}
			}
			
			# Update the players score stats
			if ( exists($main_player_hash{$player}->{'max_score'}) ) {
				if ($score > $main_player_hash{$player}->{'max_score'}) {
					$main_player_hash{$player}->{'max_score'} = $score;}
				elsif ($score < $main_player_hash{$player}->{'min_score'}) {
					$main_player_hash{$player}->{'min_score'} = $score; }
			} else {
				$main_player_hash{$player}->{'max_score'} = $score;
				$main_player_hash{$player}->{'min_score'} = $score;
			}
		}
	}

	# III.) Finally, check if anybody has gone missing from the old list...

	my $dur = 0;
	my $ip = 0;
	foreach my $old (keys %main_player_hash) {
		if ( !exists($secondary_player_hash{$old}) ) {
			# Somebody disconnected
			$dur = ($time - $main_player_hash{$old}->{'time'});	# Calculate how long they were on the server
			$ip = unpack('N', inet_aton( $main_player_hash{$old}->{'ip'} ) );		# Convert the IP string to an integer
			
			print 'Name: '. $old . "\tDisconnected.\n";

			if ($opt_verbose) {
				print ' -- Connected at: '. localtime($main_player_hash{$old}->{'time'}) . "\tDuration: ". $dur ." seconds\n";

				if ($opt_verbose > 1) {
					print Data::Dumper->Dump( [$main_player_hash{$old}], ['$main_hash{\''.$old.'\'}'] );
				}
			}

			# Update the player table with their new duration
			$dbhandle->do('UPDATE `players` SET duration='.($main_player_hash{$old}->{'duration'} + $dur).' WHERE player_id='. $main_player_hash{$old}->{'player_id'})
			or die("Unable to execute query.\n". $dbhandle->errstr ."\n");
			
			# Add an entry to the 'rcon_log' table
			$dbhandle->do('INSERT INTO `rcon_log` VALUES (NULL,'.$dtime.','.$main_player_hash{$old}->{'player_id'}.','.$ip.','.$main_player_hash{$old}->{'slot'}.',0)')
			or die("Unable to execute query.\n". $dbhandle->errstr ."\n");
			
			delete $main_player_hash{$old};
		}
	}
}

# Checks the 'error number' passed to it and returns a string describing the error.
sub error_msg($) {
	my $err = shift;
	
	# if positive or non-digit
	if ( int($err) > 0 || $err !~ m/^[+-]?\d+$/o ) {
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
		if ($backend_status == -5) {
			$timeout_last = strftime('%F %T', localtime(time));	# datetime string: 'YYYY-MM-DD HH:MM:SS'
			$timeouts++;
		}

		# Request rcon poll next time.
		$need_rcon_poll = 1;
		
		# Output error message
		print '['. localtime(time()) .'] '. error_msg($backend_status) ."\n";
	} else {
		# Catch all... 
		if ($opt_verbose > 1) { print Data::Dumper->Dump( [\$result], [qw(*Error)] ); }
		die("An unknown error occured...\nThe server's response was unrecognized.");
	}
}

# Update the "status" database with our current information.
sub db_updateStatus() {
	$last_update = $dbhandle->quote( strftime('%F %T', localtime( time() )) );	# Grab the current time ( datetime string: 'YYYY-MM-DD HH:MM:SS')
	$dbhandle->do('UPDATE `status` SET backend_status='.$backend_status.',log_lines_processed='.$log_lines_processed.',log_bytes_processed='.$log_bytes_processed.',log_last_check='.$log_last_check.',last_update='.$last_update);
}


sub db_updateServer() {
	# Only update the server information if:
	#  - we just did an rcon status update
	#  - we need an rcon poll (because either a timeout occured OR the server svars have changed)
	if ($just_rcon_polled == 1 || $need_rcon_poll == 1) {

		my ($qry, $map, $map_safe, $srv_name, $svars);
		$qry = $map = $map_safe = $srv_name = $svars = '';
		my $mapchange = 0;

		if ($urt_svars) {
			$svars = $dbhandle->quote($urt_svars);

			my @svars = split(/\\/o, $urt_svars);	# bust up the server variables string
				my %s_vars = @svars[1..$#svars];	# now store a hash of the game options

				if (!exists($s_vars{'mapname'}) || !exists($s_vars{'sv_hostname'})) {
					warn 'Error: Something is wrong with the server svars...';
				} else {
					$map		= $s_vars{'mapname'};
					$map_safe	= $dbhandle->quote( $map );
					$srv_name	= $dbhandle->quote( $s_vars{'sv_hostname'} );

					# check if the map is different than the previous one
					if ($urt_map && $urt_map ne $map) {
						$mapchange = 1;
						if ($opt_verbose) { print 'Map change. ['.$urt_map.' -> '.$map."]\n"; }
					}
					$urt_map = $map;
				}

			$qry = 'UPDATE `servers` SET timeouts='.$timeouts.',timeout_last="'.$timeout_last.'",name='.$srv_name.',current_map='.$map_safe.',svars='.$svars.' WHERE server_id='.$server_id;
		} else {
			$qry = 'UPDATE `servers` SET timeouts='.$timeouts.',timeout_last="'.$timeout_last.'" WHERE server_id='.$server_id;
		}	

		$dbhandle->do($qry) or die('Could not update database with server information...');

		# If the map changed increment the play count, and update the `map` table
		if ($map && $mapchange && exists($map_list_hash{$map})) {
			$map_list_hash{$map} += 1;
			db_updateMapList();
		}

		# If a new map is seen, add to the hash, and update the `map` table
		if ($map && !exists( $map_list_hash{$map} )) {
			$map_list_hash{$map} = 1;
			db_updateMapList();
		}

		# TODO: Update the database [gametype] table(s) with info from new svars
		# svars contain: gametype, gear information, timelimit, fraglimit, etc...
		#
		# Unfortunately there is now exact way to determine when the round/match is over.
		# So there is really no definitive method to keep track of how many rounds/matches etc..
		# - This information has to come from the log file.
	}
}

# Update the database map list with the current list of maps in the map_hash
sub db_updateMapList() {
	if ((keys %map_list_hash) > 1) {
		my $name	= '';
		my $qry		= '';
		my $times	= 0;
		my $rows	= 0;

		foreach my $map (keys %map_list_hash) {
			# TODO: Somehow store the map 'duration' and save it to the database.
			# ex: pack a string into the maplist hash that also has the 'duration'...

			$name = $dbhandle->quote($map);
			$times = int($map_list_hash{$map});
			$qry = 'UPDATE `maps` SET times_played='. $times .' WHERE map_name='. $name;

			$rows = $dbhandle->do($qry) or die('Error updating database map list...');

			if (!defined($rows) || $rows == -1) {
				print 'An error occured while updating the database map list...';
			} elsif ($rows == 0) {
				$qry = 'INSERT INTO `maps` (map_id,map_name,times_played) VALUES (NULL,'. $name .', '. $times .')';

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
		print 'Timeout occured, sleeping for '. $timeout_wait_delay .' seconds'."\n";
		sleep($timeout_wait_delay);
	} elsif ($backend_status == -7) {
		print 'Could not communicate with the server, sleeping for '.$timeout_wait_delay * 2 .' seconds'."\n";
		sleep($timeout_wait_delay * 2);
	} elsif ($backend_status == -12) {
		print 'rcon password not set yet, sleeping for 10 seconds'."\n";
		sleep($SLEEP__NO_RCON_PW);
	} elsif ($backend_status == -13) {
		print 'Waiting for server config, sleeping for 20 seconds'."\n";
		sleep($SLEEP__NO_SERVER_CFG);
	} elsif ($backend_status == -10 ) {
		print 'Bad rcon password, sleeping for 30 seconds'."\n";
		sleep($SLEEP__BAD_RCON_PW);
	} elsif ($backend_status == 10) {
		print "(Paused)\n";
		sleep($SLEEP__PAUSE_REQUEST);
	} elsif ($backend_status < 0) {
		print 'An error occured. sleeping for 15 seconds'."\n";
		sleep($SLEEP__UNKNOWN_ERROR);
	} elsif ($need_rcon_poll == 1) {
		sleep($SLEEP__NEED_RCON_POLL);	# Between 'getstatus' and 'rcon status'
	} else {
		sleep($SLEEP__DEFAULT);
	}
}

sub socket_new($) {
	my $proto = shift;
	my $hndl;
	socket($hndl, PF_INET, SOCK_DGRAM, $proto) or die("Could not open a socket.\nError: $!\n");
	return $hndl;
}

sub socket_connect($$) {
	my $addr = shift;
	my $sock_hndl = shift;
	return -2 if (!$addr or !$sock_hndl);

	my ($port, $ip) = sockaddr_in($addr);

	if (!connect($sock_hndl, $addr)) {
		print 'Could not connect to server: '.inet_ntoa($ip).':'.$port."\nError: $!\n";
		return -2;
	}
	return 1;
}

sub urt_queryServer($$$) {
	my $qry = shift;
	my $addr = shift;
	my $sock_hndl = shift;
	return -3 if (!$qry or !$addr or !$sock_hndl);

	my ($reply, $msg, $rin, $rout, $servport, $servip, $who, $port, $ip, $size, $packets);
	$reply = $msg = $rin = $rout = '';
	$packets = $size = 0;

	send( $sock_hndl, $qry, 0, $addr ) or return -3;
	vec( $rin, fileno($sock_hndl), 1 ) = 1;

	if (select($rout = $rin, undef, undef, $timeout_delay)) {
		#($who = recv($sock_hndl, $reply, $SOCK_MAX_LENGTH, 0)) or die("Error with recv: $!\n");
		if (!defined($who = recv($sock_hndl, $reply, $SOCK_MAX_LENGTH, 0))) {
			if ($! =~ m/Connection refused/o) {
				if ($opt_verbose) {
					print "* The connection was refused\n";
				}
				return -7;
			} else { die("Error with recv: $!\n"); }
		}
		$packets++;
		{ use bytes; $size = length($reply); }
		($port, $ip) = sockaddr_in($who);
		if ($who ne $addr) {
			($servport, $servip) = sockaddr_in($addr);
			print "* Response from different address ($ip:$port).\n* Expected $servip:$servport\n";
		}
		# If we only sent a 'getstatus' request then we do not need to wait for more packets.
		if ($qry !~ m/getstatus/o) {
			while ($packets < $SOCK_MAX_PACKETS && $size > $SOCK_PACKET_SIZE) {
				if (select($rout = $rin, undef, undef, $SOCK_TIMEOUT)){
					if (!defined($who = recv($sock_hndl, $msg, $SOCK_MAX_LENGTH, 0))) {
						if ($! =~ m/Connection refused/o) {
							if ($opt_verbose) {
								print "* The connection was refused\n";
							}
							return -7;
						} else { die("Error with recv: $!\n"); }
					}
					$packets++;
					{ use bytes; $size += length($msg); }
					($port, $ip) = sockaddr_in($who);
					if ($who ne $addr) {
						($servport, $servip) = sockaddr_in($addr);
						print "Response from different address ($ip:$port).\nExpected $servip:$servport\n";
					}
					$reply .= $msg;
				} else { last; }
			}
		}
		$stats{'total_packets'}	+= $packets;
		$stats{'total_bytes'}	+= $size;
		return $reply;
	} else {
		return -5; # timeout
	}
}

##### End of Subroutines #####


#============================================
#	Main Loop
#============================================

print '=' x 40 . "\n" . 'Started at: ' . localtime(time) ."\n\n";
$socket_handle = socket_new($urt_proto);
db_getStatus();
db_getServerInfo();
db_getMapList();

if ($opt_verbose > 1 && $backend_status < 0) {
	print "There was a problem last time.\nThe error was:\n";
	print "\t". error_msg($backend_status). "\n\n"; }

$backend_status = 1;

while ($main_status) {
	db_getStatus();

	# Handle any 'client_request'
	if ($client_request == -1) {
	
		dump_debug();
		
	} elsif ($client_request == -100) {		# Terminate program
	
		$dbhandle->disconnect();
		die('--> Got signal from client: Shutting down...');
	
	} elsif ($client_request == 10) {		# Pauses backend from polling server

			print "--> Got request to pause.\n";
			$backend_status = 10;

	} else {	# If no recognized client requests, then poll the server as per usual.

		if ($urt_server) {				# Have a server IP address...

			my $status = socket_connect($urt_addr, $socket_handle);
			urt_serverError($status) if (!$status);

			if ($need_rcon_poll > 0) {		# Then query the server...
				if (!$urt_rcon_pw) {
					$backend_status = -12;
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


__END__

=head1 TITLE

Rcon Monitoring Script

=head1 NAME

rcon.pl

=head1 DESCRIPTION

This program monitors an Urban Terror server and feeds the information into a database.

=head1 SYNOPSIS

rcon.pl [options]

=head1 OPTIONS

Abbreviations in square brackets.

=over 8

=item *

B<--help> [-h]

Display this help message.

=item *

B<--verbose> [-v]

Increase output verbosity.

=item *

B<-log> C</path/to/file>

Log all output to a given file.

=back

=head1 LICENSE

This program is released under a BSD style license. See LICENSE.txt file for details.

=head1 AUTHOR

jgen <jgen@lavabit.com>

=cut

