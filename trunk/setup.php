<?php
/* Setup a MySQL database for the Remote Interface.
 * Oct. 2009 - jgen
 */

require_once('config.php');
require_once('functions.php');

$fname = DB_CONFIG_FILE;
$sql_file = DB_SQL_FILE;

$db = array('driver'=>'','host'=>'','port'=>'','database'=>'','user'=>'','pass'=>'');

if (array_key_exists('makeconfig', $_REQUEST)) {

	if (!file_exists($fname)) {

		if (array_key_exists('d',$_REQUEST) && array_key_exists('h',$_REQUEST) && array_key_exists('p',$_REQUEST) && array_key_exists('db',$_REQUEST) && array_key_exists('u',$_REQUEST) && array_key_exists('pw',$_REQUEST)) {
			
			if ( empty($_REQUEST['d']) || empty($_REQUEST['h']) || empty($_REQUEST['p']) ) {
				echo "Please enter all the information for the database server.";
				exit;
			}

			if ( empty($_REQUEST['u']) || empty($_REQUEST['pw']) ) {
				echo "Please setup a username and password to connect to the server.";
				exit;
			}

		} else {
			echo('Sorry, but some important configuration information was not specified.');
			exit;
		}
		
		if (in_array($_REQUEST['d'], $DB_DRIVERS)) {
			$db['driver'] = $_REQUEST['d'];
		} else {
			echo 'Sorry, but this PHP installation does not have a database driver for "'.$_REQUEST['d'].'".';
			exit;
		}

		$host_str = trim( $_REQUEST['h'] );
		$hostaddr = trim(long2ip( ip2long( $host_str )));

		if ( strcmp($host_str, $hostaddr) == 0 ) {
			$db['host'] = $hostaddr;
		} else {
			echo 'Sorry, but the IP entered for the database server appears invalid.';
			exit;
		}

		if ( is_numeric($_REQUEST['p']) && (intval($_REQUEST['p']) > 0) && (intval($_REQUEST['p']) < pow(2,16)) ) {
			$db['port'] = $_REQUEST['p'];
		} else {
			echo 'Sorry, but that is an invalid port number "'.$_REQUEST['p'].'".';
			exit;
		}

		// These really should be checked...
		$db['database'] = $_REQUEST['db'];
		$db['user'] = $_REQUEST['u'];
		$db['pass'] = $_REQUEST['pw'];
		

		// Okay, lets try and connect to the database now.
		$db_link = mysql_connect($db['host'] .':'. $db['port'], $db['user'], $db['pass']);

		if (!$db_link) {
			echo "Could not connect to the database.\n\n";
			die('Error: ' . mysql_errorno . ' - ' . mysql_error());
		}

		// If this is not a new database, then try to select the name
		if (!array_key_exists('createnew',$_REQUEST)) {
			if (!mysql_select_db( mysql_real_escape_string($db['database']) ) ) {
				echo "Unable to select the database. (Perhaps it does not exist?)\n\n";
				mysql_close($db_link);
				die('Error: ' . mysql_errorno . ' - ' . mysql_error());
			}
		}

		if (array_key_exists('createnew',$_REQUEST)) {
			// proceed to execute SQL to create new database...
			create_db_from_file($db['database'], $sql_file, $db_link, TRUE);
		}

		// If we have not die()'ed yet, then things are probably okay
		mysql_close($db_link);


		// Time to write the config file.
		$str = var_export($db, true);

		$str = preg_replace('/array/', '%db =', $str);
		$str = preg_replace('/\)$/', ');', $str);

		$str = "<?php\n/* This file contains database information for rcon.pl\nCreated: ".date(DATE_RFC850)."\n\n". $str."\n*/\n\n";
		$str .= 'header("Expires: Mon, 26 Jul 1997 05:00:00 GMT");'."\n";
		$str .= 'header("Cache-Control: no-store, no-cache, must-revalidate");'."\n";
		$str .= 'header("Cache-Control: post-check=0, pre-check=0", false);'."\n";
		$str .= "\n?>\n";
		$str .= "<!DOCTYPE HTML PUBLIC \"-//IETF//DTD HTML 2.0//EN\">\n<html>\n<head><title>Nothing</title></head>\n<body>\n<h1>Nothing to see here</h1>\n<p>Move along please...</p>\n</body>\n</html>";

		$fp = fopen($fname, 'w', 0);

		if ($fp) {
			if (fwrite($fp, $str) === FALSE) {
				echo "Could not write to file ($fname).";
				exit;
			}

			if (fclose($fp) === FALSE) {
				echo "Could not close the file ($fname).";
				exit;
			}
		} else {
			echo "Can not open file to write ($fname).";
			exit;
		}

		output_header('Success');
		echo "<body id='doc'>\n";
		echo "<h2>Successfully wrote the database config</h2>\n<br><br>\n";
		echo "Contents:\n<br><br>\n<pre>\n";
		echo filter_var($str, FILTER_SANITIZE_SPECIAL_CHARS);
		echo "</pre>\n</body>\n</html>\n";
	} else {
		echo "A config file already exists. Aborting..";
	}
} else {
	// Output form to allow user to input database config
	output_header('Setup Database');
	output_body_setup();
}

exit;

function output_header($title) {
?>
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01//EN" "http://www.w3.org/TR/html4/strict.dtd">
<html>
<head>
	<meta http-equiv="content-type" content="text/html; charset=iso-8859-1">
	<meta http-equiv="cache-control" content="no-cache">
	<meta http-equiv="pragma" content="no-cache">
	<title><?php echo $title; ?></title>

	<!-- Pull in the YUI stylesheets for consistent look & feel -->
	<link rel="stylesheet" type="text/css" href="resource/reset/reset-fonts-grids.css">
	<link rel="stylesheet" type="text/css" href="resource/reset/base-min.css">
	<link rel="stylesheet" type="text/css" href="resource/skins/sam/skin.css">
	<style type="text/css">
		body	{ margin:0; padding:0; }
		
		form { padding:0.3em; }
		
		form span.warning {
			padding: 0.5em;
			color: red;
			font-size: 107%;
			font-style: oblique;
		}

		form label {
			display:block;
			float:left;
			width:35%;
			clear:left;
		}
		fieldset,
		fieldset div {
			margin: 0.3em;
			padding: 0.5em;
			font-size:100%;
			border: 2px groove #ccc;
		}
		fieldset legend {
			padding-left: 5px;
			padding-right: 5px;
			padding-bottom:0;
			padding-top:0;
		}
		form fieldset legend.config {
			font-size: 100%;
			margin: 0.3em;
		}
		form fieldset legend.config img {
			padding-right: 5px;
			vertical-align: middle;
		}
		form fieldset input {
			margin: 2px;
		}
	</style>
	<script language="JavaScript">
		function toggleVisibility(me){
			if (me.style.visibility=="hidden") { me.style.visibility="visible"; }
			else { me.style.visibility="hidden"; }
		}
	</script>
</head>
<?php
}

function output_body_setup() {
?>
<body id="doc">
	<h2>Setup the Database Server</h2>
	<p>Please enter the information to connect to the database server that you will be using.</p>
	<br>
	<div id="config" title="Config">
	<!--	<div class="hd">Configuration</div>	-->
		<div class="bd">
			<form id="db_config" method="post" action="" class="config">
				<fieldset id="db_config_container" class="config">
					<legend class="config"><img src="resource/database.png" height="32" width="32">Database Server</legend>

					<input type="hidden" name="makeconfig">
	
					<label for="config_driver">Driver</label>
					<select id="config_driver" name="d">
						<option label="mysql" value="mysql">MySQL</option>
					</select><br>
				
					<label for="config_db_host">IP Address:</label>
					<input type="text" maxlength="18" size="18" name="h" id="config_db_host" alt="Database Server IP Address" title="Database Server IP Address"><br>
					<label for="config_db_port">Port:</label>
					<input type="text" name="p" maxlength="8" size="10" id="config_db_port" alt="Database Server Port (default is 3306)" title="Database Server Port (default is 3306)"><br>
				</fieldset>
				<br>
				<fieldset id="login_config_container" class="config">
					<legend class="config"><img src="resource/password.png" height="32" width="32">Login Information</legend>

					<label for="config_db_user">Username:</label>
					<input type="text" maxlength="64" size="28" name="u" id="config_db_user" alt="Username to connect to the database" title="Username to connect to the database"><br>
					<label for="config_db_pw">Password:</label>
					<input type="password" maxlength="64" size="28" name="pw" id="config_db_pw" alt="Password to connect to the database" title="Password to connect to the database"><br>
				</fieldset>
				<br>
				<fieldset id="schema_config_container" class="config">
					<legend class="config"><img src="resource/kexi.png" height="32" width="32">Database Name</legend>
					<label for="config_db_name">Database Name:</label>
					<input type="text" maxlength="64" size="28" name="db" id="config_db_name" alt="The name of the Schema to use" title="The name of the Schema to use">
					<br>
					<span id="config_db_overwrite" class="warning" style="visibility:hidden">Warning this will delete any existing Database with that name!</span>
					<br>
					<label for="config_db_createnew">Create New ?</label>
					<input type="checkbox" name="createnew" id="config_db_createnew" onclick="toggleVisibility(document.getElementById('config_db_overwrite'));">
				</fieldset>
				<br>
				<center><input type="submit" value="Save Config" class="submit"></center>
			</form>
		</div>
	</div>
</body>
</html>
<?php } ?>