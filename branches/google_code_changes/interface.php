<?php
/*
 *	Remote Interface (for Urban Terror)
 *	Author: Jeff Genovy (jgen)
 *	Date: August 2009
 *	BSD Licensed
 */

// HTTP/1.1 --- Don't cache the page
header("Expires: Mon, 26 Jul 1997 05:00:00 GMT");
header("Cache-Control: no-store, no-cache, must-revalidate");
header("Cache-Control: post-check=0, pre-check=0", false);
// always modified
header("Last-Modified: " . gmdate("D, d M Y H:i:s") . " GMT");

// TODO: centralized config for database - shared between rcon.pl and interface.php
$db_host = 'localhost';
$db_port = 13390;
$db_user = 'rconlogs';
$db_pass = 'urtlogs';

$db_name = 'rcon_db';
$db_table = '';


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

	
	$qry = 'SELECT * FROM `servers`';
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
		'data'=>$data
	);

	echo(json_encode($returnValue));

	mysql_free_result($results);

} else if (array_key_exists('server_config', $_REQUEST)) {

	echo("\nUpdate the server config...\n");
	// validation required

} else if (array_key_exists('server_pw', $_REQUEST)) {

	echo("\nUpdate the server Rcon password...\n");
	// validation required


} else if (array_key_exists('search_name', $_REQUEST)) {
	/* SEARCH FOR NAME */

	if (array_key_exists('name_text', $_REQUEST)) {
		echo( search_name($_REQUEST['name_text'], $db_link) );
	} else {
		echo('No player name given');
	}

} else if (array_key_exists('search_ip', $_REQUEST)) {
	/* SEARCH FOR IP ADDRESS */

	if (array_key_exists('ip_text', $_REQUEST)) {
		echo( search_ip_addr($_REQUEST['ip_text'], $db_link) );
	} else {
		echo('No IP address given');
	}

} else {
	echo('Invalid request');

	if ($_REQUEST) {
		echo("\n---Variable Dump---\n");
		print_r($_REQUEST);
	}
}


function search_ip_addr($ip, $link)
{
	if ($ip && $link) {
		$qry = 'SELECT * FROM `ips` WHERE `ip_txt` LIKE "';

		$search_addr = str_replace("%", "\%", $ip);
		$search_addr = str_replace("_", "\_", $search_addr);
		$search_addr = str_replace("?", "_", $search_addr);
		$search_addr = str_replace("*", "%", $search_addr);
		$qry .= mysql_real_escape_string($search_addr, $link) . '" ORDER BY `ip`';

		$results = mysql_query($qry, $link);

		if (!$results) { echo "Error preforming query.\n"; echo 'Error: ' . mysql_error(); die(); }


		$data = array();
		$num_rows = mysql_num_rows($results);

		while ( $row = mysql_fetch_assoc($results) ) {
			$data[] = $row;
		}

		mysql_free_result($results);
	
		// Convert & Replace the packed data string of player IDs to an array of ints
		foreach ($data as &$row) {
			$id_str = $row['player_ids'];
			$length = strlen($id_str);
			$num_ids = $length / 4;
			$offset = $length % 4;
			$ids = array();
			$tmp = array();		// hack because PHP actually uses 'ordered maps' and NOT arrays.

			if ($offset != 0 || $length == 0) {
				return 'Error, problem with the database.'; }

			for ($i=0; $i<$num_ids; $i++) {
				$tmp = unpack("N", substr($id_str, $i*4, 4) );
				$ids[] = $tmp[1];
			}

			$row['player_ids'] = $ids;
			$row['player_names'] = player_ids_to_names($ids, $link);
		}
		unset($row);

		$returnValue = array(
			'rows'=>$num_rows,
			'type'=>'ip',
			'data'=>$data
		);
	
		return json_encode($returnValue);
	}
	return false;
}

function search_name($name, $link)
{
	if ($name && $link) {

		$qry = 'SELECT * FROM `players` WHERE `name` LIKE "';

		$search_name = str_replace("%", "\%", $name);
		$search_name = str_replace("_", "\_", $search_name);
		$search_name = str_replace("?", "_", $search_name);
		$search_name = str_replace("*", "%", $search_name);
		$qry .= mysql_real_escape_string($search_name, $link) . '" ORDER BY `player_id`';

		$results = mysql_query($qry, $link);

		if (!$results) { echo "Error preforming query.\n"; echo 'Error: ' . mysql_error(); die(); }


		$data = array();
		$num_rows = mysql_num_rows($results);

		while ( $row = mysql_fetch_assoc($results) ) {
			$data[] = $row;
		}

		mysql_free_result($results);
	
		foreach ($data as &$row) {
			$ip_str = $row['ips'];
			$length = strlen($ip_str);
			$num_ips = $length / 4;
			$offset = $length % 4;
			$ips = array();
			$tmp = array();		// hack because PHP actually uses 'ordered maps' and NOT arrays.

			if ($offset != 0 || $length == 0) {
				return 'Error, problem with the database.'; }

			for ($i=0; $i<$num_ips; $i++) {
				$tmp = unpack("N", substr($ip_str, $i*4, 4) );
				$ips[] = long2ip($tmp[1]);			// convert to a human-readable address
//				$ips[] = sprintf('%u', $tmp[1]);		// hack as PHP does not support unsigned ints
			}

			$row['ips'] = $ips;
		}
		unset($row);

		$returnValue = array(
			'rows'=>$num_rows,
			'type'=>'name',
			'data'=>$data
		);
	
		return json_encode($returnValue);
	}
	return false;
}

// Takes an array of numeric 'player_ids' and returns a JSON string of the co-responding player names
// Example:
// $ids = [1,2,3,4]
// returns: "[\"Name_One\",\"Name Two\",\"NameNumberThree\",\"I Am Number Four\"]"
function player_ids_to_names($ids, $link)
{
	if ($ids && $link) {
	
		$qry = 'SELECT `name` FROM `players` WHERE `player_id` IN (';
		$tmp = '';

		foreach ($ids as &$id) {
			$tmp .= filter_var($id, FILTER_SANITIZE_NUMBER_INT) . ',';
		}
		
		$qry .= rtrim($tmp, ',') . ')';

		$results = mysql_query($qry, $link);

		if (!$results) { echo "Error preforming query.\n"; echo 'Error: ' . mysql_error(); die(); }

		$data = array();

		while ( $row = mysql_fetch_row($results) ) {
			$data[] = $row[0];
		}

		mysql_free_result($results);
		
		return json_encode($data);
	}
	return false;
}

mysql_close($db_link);

?>
