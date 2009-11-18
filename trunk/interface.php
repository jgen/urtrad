<?php
/* Remote Interface for Urban Terror
 * August 2009 - jgen
 */

require_once('config.php');

$db_config = read_db_config_file();

$db_link = mysql_connect($db_config['host'] .':'. $db_config['port'], $db_config['user'], $db_config['pass']);

if (!$db_link) {
	echo "Could not connect to the database.\n\n";
	die('Error: ' . mysql_errorno . ' - ' . mysql_error());
}

if (!mysql_select_db( mysql_real_escape_string($db_config['database']) ) ) {
	echo "Unable to select database.\n\n";
	die('Error: ' . mysql_errorno . ' - ' . mysql_error());
}

$qry = '';


// HTTP/1.1 -- Don't cache the page.
// (We don't want the browser to use any stale content.)
header('Expires: Mon, 26 Jul 1997 05:00:00 GMT');
header('Cache-Control: no-store, no-cache, must-revalidate');
header('Cache-Control: post-check=0, pre-check=0', false);
header('Last-Modified: '. gmdate('D, d M Y H:i:s') .' GMT'); // Always modified


if (array_key_exists('serverstatus', $_REQUEST)) {

	$qry = 'SELECT * FROM `status`';
	$results = mysql_query($qry, $db_link);

	if (!$results) { echo "Error preforming query.\n"; echo 'Error: ' . mysql_error(); die(); }
	if (mysql_num_rows($results) != 1) { echo "There is a problem with the status table in the database."; die(); }

	$returnValue = array( 'backend' => mysql_fetch_assoc($results) );

	mysql_free_result($results);

	// Changed so that it does not show the rcon password. -- Was $qry = 'SELECT * FROM `servers`';
	$qry = 'SELECT server_id,status,ip,port,name,current_map,timeouts,timeout_last,timeout_delay,timeout_wait_delay,svars FROM `servers`';
	$results = mysql_query($qry, $db_link);

	if (!$results) { echo "Error preforming query.\n"; echo 'Error: ' . mysql_error(); die(); }
	if (mysql_num_rows($results) != 1) { echo "There is a problem with the servers table in the database."; die(); }
	
	$returnValue['server'] = mysql_fetch_assoc($results);

	mysql_free_result($results);

	echo( json_encode($returnValue) );

} else if (array_key_exists('status', $_REQUEST)) {

	$qry = 'SELECT server_id,status,ip,port,name,current_map,svars FROM `servers`';
	$results = mysql_query($qry, $db_link);

	if (!$results) { echo "Error preforming query.\n"; echo 'Error: ' . mysql_error(); die(); }
	if (mysql_num_rows($results) != 1) { echo "There is a problem with the servers table in the database."; die(); }
	
	$returnValue = array( 'server' => mysql_fetch_assoc($results) );

	mysql_free_result($results);

	echo( json_encode($returnValue) );
	
} else if (array_key_exists('players', $_REQUEST)) {

	/* Do some kind of caching to a file based on current time()
	 * to reduce database queries.
	 *
	 * ex: Make file called 'playercache_'.time() and check if (current time() > (filetime + 3s))
	 *
	 * This would work, but how to you remove the files?
	 * -There will be an overhead associated with creating and deleting files,
	 *  that may negate any savings the caching gives you...
	 * -This would probably only be worthwhile if you are being hit with many many database queries..
	 */
	
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
/*		// some kind of user account validation should be required
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
*/
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

	// For debugging...
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
