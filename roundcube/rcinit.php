<?php
/*******************************************************************
 * Tool to test config, DB connectivity, DB schema initialization
 * and to initialize DB schema.
 *******************************************************************/

ini_set('error_reporting', E_ALL &~ (E_NOTICE | E_STRICT));
ini_set('display_errors', 1);

define('INSTALL_PATH', '/roundcube/');
define('RCUBE_INSTALL_PATH', INSTALL_PATH);
define('RCUBE_CONFIG_DIR', INSTALL_PATH . 'config/');

$include_path  = INSTALL_PATH . 'program/lib' . PATH_SEPARATOR;
$include_path .= INSTALL_PATH . 'program/include' . PATH_SEPARATOR;
$include_path .= ini_get('include_path');

set_include_path($include_path);

require INSTALL_PATH . 'vendor/autoload.php'; // include composer autoloader
require_once 'Roundcube/bootstrap.php'; // deprecated aliases (to be removed)
require_once 'bc.php';

$RCI = rcmail_install::get_instance();
$RCI->load_config();

if (!$RCI->configured) {
	echo "Your configuration is incomplete!\n";
	exit(1);
}

if ($RCI->legacy_config) {
	echo "Your configuration is deprecated and needs to be migrated!\n";
	exit(1);
}

$a = count($argv) == 2 ? $argv[1] : '';

switch($a) {
	case 'testconnection':
	case 'testschema':
	case 'initschema':
		// Connect to DB
		$DB = rcube_db::factory($RCI->config['db_dsnw'], '', false);
		$DB->set_debug((bool)$RCI->config['sql_debug']);
		$DB->db_connect('w');

		if (($db_error_msg = $DB->is_error())) {
			echo "DB connection failed: $db_error_msg\n";
			exit(2);
		}
}

// ATTENTION: For simplicity the testschema and initschema actions are split
//   into two separate command line calls since one call produces errors
//   due to stateful objects which would have to be cleaned up.
switch ($a) {
	case 'testconfig':
		echo "Configuration verified\n";
		break;
	case 'testconnection':
		echo "Database connectivity verified\n";
		break;
	case 'testschema':
		$DB->query('SELECT COUNT(*) FROM ' . $DB->quote_identifier($RCI->config['db_prefix'] . 'users'));

		if (($db_error_msg = $DB->is_error())) {
			echo "Database is uninitialized\n";
			exit(3);
		}
		break;
	case 'initschema':
		echo "Initializing database\n";

		if (!$RCI->init_db($DB)) {
			print "\nFailed to initialize DB schema\n";
			exit(4);
		}

		echo "Database initialized\n";
		break;
	default:
		echo "Invalid argument supplied: '$a'. Supported args are testconfig, testconnection, testschema, initschema\n";
		exit(1);
}
