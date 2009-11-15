<?php
/**
 * config.php
 *
 * This file contains all constants and special variables
 * to make it easier to configure the script as requried.
 *
 */


define('DB_CONFIG_FILE', 'db_config.php');
define('DB_CONFIG_MAXSIZE', 1024);

define('DB_SQL_FILE', 'radmode_database.sql');

$DB_DRIVERS = array ('mysql');



/**
 * read_db_config_file()
 *
 * Read in the config file for the database.
 * Returns the config as an array.
 *
 * Ideas:
 * Perhaps just read it once, store an md5sum of the file
 * and only re-read the config file if the md5sum changes
 * (ie: the file contents have changed)?
 *
 * Tested: Caching the config file does not have any
 *	noticeable performance benefit on my Virtual Machine...
 */
function read_db_config_file() {

	$fname = DB_CONFIG_FILE;
	$fsize = 0;
	$fcontent ='';
	$db_config = array('driver'=>'','host'=>'','port'=>'','database'=>'','user'=>'','pass'=>'');

	if (file_exists($fname)) {
		if (($fsize = filesize($fname)) > DB_CONFIG_MAXSIZE) {
			echo 'The config file seems quite large. It really should be rather small. Please look into this...';
			echo "\n\nFilename: $fname\nSize: $fsize\n\n\n(The file should be under ".DB_CONFIG_MAXSIZE.")"; exit;
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

	// Put the contents of the first comment ( /* This style */ ) into $match[1]
	if (preg_match('/^\s*<\?php\s*[^\/\*]*\/\*([^\*\/]*)\*\//', $fcontent, $match) == 0) {
		echo "Sorry, but I could not correctly read the config file."; exit;
	}
	if (empty ($match[1])){
		echo "The database config must be put in the first multi-line comment in the file."; exit;
	}

	/* Store the contents of the config hash in $config_hash[1]
	 *
	 * There is a Possible Bug here if the username, password, etc
	 * contains the two characters ');' in a row.
	 *   Hopefully it won't...
	 */
	if (preg_match('/%db\s*=\s*\(([^\);]*)\);/', $match[1], $config_hash) == 0) {
		echo "The config section of the file is missing."; exit;
	}
	if (empty ($config_hash[1])) {
		echo "The config section is empty."; exit;
	}

	// Database driver
	if (preg_match("/'driver'\s*=>\s*'([^']*)'/", $config_hash[1], $match) == 0) {
		echo "No database driver specified."; exit;
	} else {
		// Check that we have a driver for that type of database.
		if (in_array($match[1],  $GLOBALS['DB_DRIVERS'])) {
			$db_config['driver'] = $match[1];
		} else {
			echo 'Sorry, but this program currently does not support the "'.$match[1].'" database driver.'; exit;
		}
	}

	// Database host / address
	if (preg_match("/'host'\s*=>\s*'([^']*)'/", $config_hash[1], $match) == 0) {
		echo "No database host specified."; exit;
	} else {
		// Check that the given host address is a valid IP address.
		$host_str = trim( $match[1] );
		$hostaddr = trim(long2ip( ip2long( $host_str )));

		if ( strcmp($host_str, $hostaddr) == 0 ) {
			$db_config['host'] = $hostaddr;
		} else {
			echo 'Sorry, but the IP ('.$match[1].') entered for the database server appears invalid.'; exit;
		}
	}

	// Database server host port
	if (preg_match("/'port'\s*=>\s*'([^']*)'/", $config_hash[1], $match) == 0) {
		echo "No port number was specified."; exit;
	} else {
		// Check that the port number is valid (0 - 65536)
		if ( is_numeric($match[1]) && (intval($match[1]) > 0) && (intval($match[1]) < pow(2,16)) ) {
			$db_config['port'] = intval($match[1]);
		} else {
			echo 'Sorry, but that is an invalid port number "'. $match[1] .'".'; exit;
		}
	}

	/* --------------------------------------------
	 *  These really should be checked as well... 
	 * -------------------------------------------- */

	// Database schema to use
	if (preg_match("/'database'\s*=>\s*'([^']*)'/", $config_hash[1], $match) == 0) {
		echo "No database was specified."; exit;
	}
	$db_config['database'] = $match[1];

	// Database user name
	if (preg_match("/'user'\s*=>\s*'([^']*)'/", $config_hash[1], $match) == 0) {
		echo "No user name was specified."; exit;
	}
	$db_config['user'] = $match[1];

	// Database user password
	if (preg_match("/'pass'\s*=>\s*'([^']*)'/", $config_hash[1], $match) == 0) {
		echo "No password was specified.";
		$db_config['pass'] = '';
	}
	$db_config['pass'] = $match[1];

	return $db_config;
}

?>