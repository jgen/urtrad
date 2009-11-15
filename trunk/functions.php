<?php
/**
 * functions.php
 *
 * Collection of various functions that assist with script operation.
 *
 */



/* Create a MySQL database schema from a file, with optional overwrite.
 * Please: _Backup your data_ before overwriting a database.
 */
function create_db_from_file($name, $file, $link, $overwrite = FALSE) {

	if (!$name) { die("No database name passed to create_db_from_file."); }
	if (!$file) { die("No filename specified to create_db_from_file."); }
	if (!$link) { die("No database link passed to create_db_from_file."); }

	$name = mysql_real_escape_string($name, $link);

	// Check if the database name already exists
	if (mysql_select_db($name, $link)) {
		if ($overwrite) {
			// delete the existing database.
			$qry = 'DROP DATABASE `'. $name .'`';
			if (mysql_query($qry, $link) === FALSE) {
				echo "Error: Could not delete the old database.\n";
				die('Error: ' . mysql_errorno . ' - ' . mysql_error());
			}
		} else {
			die("Error: A database already exists with that name.");
		}
	}

	$qry = 'CREATE SCHEMA IF NOT EXISTS `'.$name.'` DEFAULT CHARACTER SET latin5';

	if (mysql_query($qry, $link) === FALSE) {
		echo "Error: Could not create the new database.\n";
		die('Error: ' . mysql_errorno . ' - ' . mysql_error());
	}
	if (!mysql_select_db($name, $link)) {
		echo "Could not select the newly created database.\n";
		die('Error: ' . mysql_errorno . ' - ' . mysql_error());
	}

	execute_sql_file($file, $link);
}

/* Load in a SQL file (ex: commands.sql) and
 * execute it against a MySQL database link.
 *
 * Note: THERE IS NO CHECKING DONE ON THE SQL ITSELF
 */
function execute_sql_file($fname, $link) {

	if (!$fname || !$link) { die("Invalid call to function execute_sql_file().\n"); }

	if (file_exists($fname)) {
		if (($fsize = filesize($fname)) > pow(2,16) ) {
			echo 'The SQL file seems quite large. It really should not be this big. Please look into this...';
			echo "\n\nFilename: $fname\nSize: $fsize\n\n\n"; exit;
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
		echo "The requested SQL file does not exist or is unaccessable. (Maybe no read permission on the file?)"; exit;
	}

	$queries = preg_split("/;+(?=([^'|^\\\']*['|\\\'][^'|^\\\']*['|\\\'])*[^'|^\\\']*[^'|^\\\']$)/", $fcontent);

	foreach ($queries as $qry) {
		if (strlen(trim($qry)) > 0) {
			if (mysql_query($qry, $link) === FALSE) {
				echo "There was error executing one of the SQL statements.\n";
			}
		}
	}
}






?>