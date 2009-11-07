<?php
/* Remote Interface for Urban Terror
 * August 2009 - jgen
 */

// HTTP/1.1 -- Don't cache the page.
// (We don't want the browser to use any stale content.)
header('Expires: Mon, 26 Jul 1997 05:00:00 GMT');
header('Cache-Control: no-store, no-cache, must-revalidate');
header('Cache-Control: post-check=0, pre-check=0', false);
header('Last-Modified: '. gmdate('D, d M Y H:i:s') .' GMT'); // Always modified

/* --- Read in the config file for the database ---
 *
 * Perhaps just read it once, store an md5sum of the file
 * and only re-read the config file if the md5sum changes
 * (ie: the file contents have changed)?
 *
 * -Tested-
 * Caching the config file does not have any noticeable
 * performance effect on my Virtual Machine...
 */

$database_drivers = array ('mysql');
$fname = 'db_config.php';
$fsize = 0;
$fcontent ='';
$db_config = array('driver'=>'','host'=>'','port'=>'','database'=>'','user'=>'','pass'=>'');

if (file_exists($fname)) {
	if (($fsize = filesize($fname)) > 1024) {
		echo 'The config file seems quite large. It really should be rather small. Please look into this...';
		echo "\n\nFilename: $fname\nSize: $fsize\n\n\n(The file should be under 1Kb)"; exit;
	}
	$fp = fopen($fname, 'r', 0);

	if ($fp) {
		$fcontent = file_get_contents($fname);

		if (fclose($fp) === FALSE) {
			echo "Could not close the file ($fname)."; exit;
		}
	} else {
		echo "Can not open file to read ($fname)."; exit;
	}
} else {
	echo "The database config is missing."; exit;
}

// Put the contents of the first comment ( /* This style */ ) into $matches[1]
if (preg_match('/^\s*<\?php\s*[^\/\*]*\/\*([^\*\/]*)\*\//', $fcontent, $matches) == 0) {
	echo "Sorry, but I could not correctly read the config file."; exit;
}
if (empty ($matches[1])){
	echo "The database config must be put in the first multi-line comment in the file."; exit;
}

/* Store the contents of the config hash in $config_hash[1]
 *
 * There is a Possible Bug here if the username, password, etc
 * contains the two characters ');' in a row.
 *   Hopefully it won't...
 */
if (preg_match('/%db\s*=\s*\(([^\);]*)\);/', $matches[1], $config_hash) == 0) {
	echo "The config section of the file is missing."; exit;
}
if (empty ($config_hash[1])) {
	echo "The config section is empty."; exit;
}

// Read in each part of the config...
if (preg_match("/'driver'\s*=>\s*'([^']*)'/", $config_hash[1], $matchdriver) == 0) {
	echo "No database driver specified."; exit;
}
$db_config['driver'] = $matchdriver[1];

if (preg_match("/'host'\s*=>\s*'([^']*)'/", $config_hash[1], $matchhost) == 0) {
	echo "No database host specified."; exit;
}
$db_config['host'] = $matchhost[1];

if (preg_match("/'port'\s*=>\s*'([^']*)'/", $config_hash[1], $matchport) == 0) {
	echo "No port number was specified."; exit;
}
$db_config['port'] = $matchport[1];

if (preg_match("/'database'\s*=>\s*'([^']*)'/", $config_hash[1], $matchdb) == 0) {
	echo "No database was specified."; exit;
}
$db_config['database'] = $matchdb[1];

if (preg_match("/'user'\s*=>\s*'([^']*)'/", $config_hash[1], $matchuser) == 0) {
	echo "No user name was specified."; exit;
}
$db_config['user'] = $matchuser[1];

if (preg_match("/'pass'\s*=>\s*'([^']*)'/", $config_hash[1], $matchpass) == 0) {
	echo "No password was specified.";
	$db_config['pass'] = '';
}
$db_config['pass'] = $matchpass[1];


/* Check the config & copy it over the the database variables. */

// Check that the given host address is a valid IP address.
$host_str = trim( $db_config['host'] );
$hostaddr = trim(long2ip( ip2long( $host_str )));

if ( strcmp($host_str, $hostaddr) == 0 ) {
	$db_host = $hostaddr;
} else {
	echo 'Sorry, but the IP entered for the database server appears invalid.'; exit;
}
// Check that the port number is valid (0 - 65536)
if ( is_numeric($db_config['port']) && (intval($db_config['port']) > 0) && (intval($db_config['port']) < pow(2,16)) ) {
	$db_port = intval($db_config['port']);
} else {
	echo 'Sorry, but that is an invalid port number "'. $db_config['port'] .'".'; exit;
}
// Check that we have a driver for that type of database.
if (in_array($db_config['driver'], $database_drivers)) {
	$db_driver = $db_config['driver'];
} else {
	echo 'Sorry, but this program currently does not support the "'.$db_config['driver'].'" database driver.'; exit;
}

// These really should be checked as well...
$db_user = $db_config['user'];
$db_pass = $db_config['pass'];
$db_name = $db_config['database'];


/*----- Now the database config has been loaded, main part starts -----*/

$qry = '';

$db_link = mysql_connect($db_host .':'. $db_port, $db_user, $db_pass);

if (!$db_link) {
	echo "Could not connect to the database.\n\n";
	die('Error: ' . mysql_errorno . ' - ' . mysql_error());
}

if (!mysql_select_db( mysql_real_escape_string($db_name) ) ) {
	echo "Unable to select database.\n\n";
	die('Error: ' . mysql_errorno . ' - ' . mysql_error());
}



if (array_key_exists('status', $_REQUEST)) {

	$qry = 'SELECT * FROM `status`';
	$results = mysql_query($qry, $db_link);

	if (!$results) { echo "Error preforming query.\n"; echo 'Error: ' . mysql_error(); die(); }
	if (mysql_num_rows($results) != 1) { echo "There is a problem with the Status table in the database."; die(); }

	$returnValue = array( 'backend' => mysql_fetch_assoc($results) );

	mysql_free_result($results);

	
	//$qry = 'SELECT * FROM `servers`';
	$qry = 'SELECT server_id,status,ip,port,name,current_map,timeouts,timeout_last,timeout_delay,timeout_wait_delay,svars FROM `servers`';
	$results = mysql_query($qry, $db_link);

	if (!$results) { echo "Error preforming query.\n"; echo 'Error: ' . mysql_error(); die(); }
	if (mysql_num_rows($results) != 1) { echo "There is a problem with the Status table in the database."; die(); }
	
	$returnValue['server'] = mysql_fetch_assoc($results);

	mysql_free_result($results);


	echo( json_encode($returnValue) );

} else if (array_key_exists('players', $_REQUEST)) {

	// Do some kind of caching to a file based on current time()
	// to reduce database queries.

	// make file called "playercache_time()"
	// check if (current time() > (filetime + 3s))

	$qry = 'SELECT * FROM `current_players`';
	$results = mysql_query($qry, $db_link);

	if (!$results) { echo "Error preforming query.\n"; echo 'Error: ' . mysql_error(); die(); }

	$data = array();
	$rows = mysql_num_rows($results);

	while ( $row = mysql_fetch_assoc($results) ) {
		$data[] = $row;
	}

	$returnValue = array(
		'rows'=>$rows,
		'data'=>$data );

	echo(json_encode($returnValue));

	mysql_free_result($results);

} else if (array_key_exists('server_config', $_REQUEST)) {
	/* UPDATE THE SERVER CONFIG */
		// some kind of user account validation should be required
	$serv_ip = '';
	$serv_port = '';
	$serv_timeout = '';
	$serv_timeout_wait = '';

	if (array_key_exists('ip', $_REQUEST) && array_key_exists('port', $_REQUEST) && array_key_exists('timeout_delay', $_REQUEST) && array_key_exists('timeout_wait', $_REQUEST)) {
		// Check the incomming config values.
		$ip_str = trim( $_REQUEST['ip'] );
		$ipaddr = trim(long2ip( ip2long( $ip_str )));

		if ( strcmp($ip_str, $ipaddr) == 0 ) {
			$serv_ip = $ipaddr;
		} else {
			echo 'Sorry, but the IP entered for the server appears invalid.'; exit;
		}

		if (is_numeric($_REQUEST['port']) && (intval($_REQUEST['port']) > 0) && (intval($_REQUEST['port']) < pow(2,16)) ) {
			$serv_port = intval($_REQUEST['port']);
		} else {
			echo 'Sorry, but that is an invalid port number "'.$_REQUEST['port'].'".'; exit;
		}
		if (is_numeric($_REQUEST['timeout_delay']) && (intval($_REQUEST['timeout_delay']) > 0) && (intval($_REQUEST['timeout_delay']) < pow(2,8)) ) {
			$serv_timeout = intval($_REQUEST['timeout_delay']);
		} else {
			echo 'Sorry, but that is an invalid timeout delay "'.$_REQUEST['timeout_delay'].'".'; exit;
		}
		if (is_numeric($_REQUEST['timeout_wait']) && (intval($_REQUEST['timeout_wait']) > 0) && (intval($_REQUEST['timeout_wait']) < pow(2,8)) ) {
			$serv_timeout_wait = intval($_REQUEST['timeout_wait']);
		} else {
			echo 'Sorry, but that is an invalid timeout wait delay "'.$_REQUEST['timeout_wait'].'".'; exit;
		}
	} else {
		echo "Error: Some import information was missing from the server config request."; exit;
	}

	$qry = 'SELECT * FROM `servers`';
	$results = mysql_query($qry, $db_link);
	if (!$results) { echo "Error preforming query.\n"; echo 'Error: ' . mysql_error(); die(); }

	$rows = mysql_num_rows($results);

	if ($rows == 0) {
		$qry = 'INSERT INTO `servers` (status,ip,port,name,timeouts,timeout_last,timeout_delay,timeout_wait_delay,rcon_pw,svars) VALUES (0,INET_ATON("'.$serv_ip.'"),'.$serv_port.',"",0,0,'.$serv_timeout.','.$serv_timeout_wait.',"","")';

		$results = mysql_query($qry, $db_link);
		if (!$results) { echo "Error preforming query.\n"; echo 'Error: ' . mysql_error(); die(); }
	} else {
		$qry = 'UPDATE `servers` SET ip=INET_ATON("'.$serv_ip.'"),port='.$serv_port.',timeout_delay='.$serv_timeout.',timeout_wait_delay='.$serv_timeout_wait.' WHERE server_id=1';
		$results = mysql_query($qry, $db_link);
		if (!$results) { echo "Error preforming query.\n"; echo 'Error: ' . mysql_error(); die(); }
	}

} else if (array_key_exists('server_pw', $_REQUEST)) {
	/* UPDATE THE RCON PASSWORD */
		// some kind of user account validation should be required
/*
	$qry = 'SELECT * FROM `servers`';
	$results = mysql_query($qry, $db_link);
	if (!$results) { echo "Error preforming query.\n"; echo 'Error: ' . mysql_error(); die(); }
	$rows = mysql_num_rows($results);

	if ($rows == 0) {
		echo "Error: No servers are currently setup."; exit;
	} else {
		$pw = mysql_real_escape_string($_REQUEST['pw'], $db_link);
		$qry = 'UPDATE `servers` SET rcon_pw="'.$pw.'" WHERE server_id=1';
		$results = mysql_query($qry, $db_link);
		if (!$results) { echo "Error preforming query.\n"; echo 'Error: ' . mysql_error(); die(); }
	}
*/
} else if (array_key_exists('search_name', $_REQUEST)) {
	/* SEARCH FOR NAME */
	if (array_key_exists('name_text', $_REQUEST)) {
		echo( search_db($_REQUEST['name_text'], 'search_name', $db_link) );
	} else {
		echo('No player name given');
	}
} else if (array_key_exists('search_ip', $_REQUEST)) {
	/* SEARCH FOR IP ADDRESS */
	if (array_key_exists('ip_text', $_REQUEST)) {
		echo( search_db($_REQUEST['ip_text'], 'search_ip', $db_link) );
	} else {
		echo('No IP address given');
	}
} else if (array_key_exists('search_log_name', $_REQUEST)) {
	/* SEARCH rcon_log TABLE FOR NAME */
	if (array_key_exists('name', $_REQUEST)) {
		echo( search_db($_REQUEST['name'], 'search_log_name', $db_link) );
	} else {
		echo('No name given to search the log for.');
	}
} else if (array_key_exists('search_log_name', $_REQUEST)) {
	/* SEARCH rcon_log TABLE FOR IP ADDRESS */
	if (array_key_exists('ip', $_REQUEST)) {
		echo( search_db($_REQUEST['ip'], 'search_log_ip', $db_link) );
	} else {
		echo('No IP address given to search the log for.');
	}
} else {
	echo('Invalid request');

	if ($_REQUEST) {
		echo("\n---Variable Dump---\n");
		print_r($_REQUEST);
	}
}

function search_db($value, $type, $link) {
	if ($value && $type && $link) {
		$qry = '';
		$str = '';		

		$str = str_replace("%", "\%", $value);
		$str = str_replace("_", "\_", $str);
		$str = str_replace("?", "_", $str); // _ = single character wildcard in SQL
		$str = str_replace("*", "%", $str); // % = multi  character wildcard in SQL

		$str = mysql_real_escape_string($str, $link);

		switch ($type) {
			case 'search_name':
				$qry = 'SELECT p.player_id, p.name, p.duration, date_format(p.creation, "%Y %m %d %T") AS creation, i.ip, i.ip_text
					FROM players p JOIN ips i USING(player_id) WHERE p.name LIKE "'. $str .'" ORDER BY p.player_id, i.ip';
				break;
			case 'search_ip':
				$qry = 'SELECT i.player_id, i.ip, i.ip_text, p.name, date_format(i.creation, "%Y %m %d %T") AS creation
					FROM ips i JOIN players p USING(player_id) WHERE i.ip_text LIKE "'. $str . '" ORDER BY i.ip, i.player_id';
				break;
			case 'search_log_name':
				$qry = 'SELECT r.log_id, date_format(r.`datetime`,"%Y %m %d %T") AS log_time, r.ip, r.slot, r.`action`,
						p.player_id, p.name, date_format(p.creation,"%Y %m %d %T") AS player_created
					FROM rcon_log r JOIN players p USING(player_id)
					WHERE r.player_id IN (SELECT pl.player_id FROM players pl WHERE pl.name LIKE "'. $str .'") ORDER BY log_time';
				break;
			case 'search_log_ip':
				$qry = 'SELECT r.log_id, date_format(r.`datetime`,"%Y %m %d %T") AS log_time, r.ip, r.slot, r.`action`,
						p.player_id, p.name, date_format(p.creation,"%Y %m %d %T") AS player_created 
					FROM rcon_log r JOIN players p USING(player_id)
					WHERE r.player_id IN (SELECT i.player_id FROM ips i WHERE i.ip_text LIKE "'. $str .'") ORDER BY log_time';
				break;
			default:
				echo('Unsupported search type specified.');
				return;
				break;
		}

		$results = mysql_query($qry, $link);

		if (!$results) { echo "Error preforming query.\n"; echo 'Error: ' . mysql_error(); die(); }

		$data = array();
		$num_rows = mysql_num_rows($results);

		while ( $row = mysql_fetch_assoc($results) ) {
			$data[] = $row;
		}

		mysql_free_result($results);
	
		$returnValue = array(
			'rows' => $num_rows,
			'type' => $type,
			'data' => $data
		);
		return json_encode($returnValue);
	}
	echo('Incorrect call to function search_db.');
	return false;
}

mysql_close($db_link);

?>
