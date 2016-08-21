<?php

ini_set('error_reporting', E_ALL &~ (E_NOTICE | E_STRICT));
ini_set('display_errors', 1);

define('INSTALL_PATH', realpath(__DIR__ . '/../').'/');
define('RCUBE_INSTALL_PATH', INSTALL_PATH);
define('RCUBE_CONFIG_DIR', INSTALL_PATH . 'config/');

$include_path  = INSTALL_PATH . 'program/lib' . PATH_SEPARATOR;
$include_path .= INSTALL_PATH . 'program/include' . PATH_SEPARATOR;
$include_path .= ini_get('include_path');

set_include_path($include_path);

require_once 'Roundcube/bootstrap.php';
// deprecated aliases (to be removed)
require_once 'bc.php';

if (function_exists('session_start'))
  session_start();

$RCI = rcmail_install::get_instance();
$RCI->load_config();


// Init DB
$DB = rcube_db::factory($RCI->config['db_dsnw'], '', false);
$DB->set_debug((bool)$RCI->config['sql_debug']);
$DB->db_connect('w');

if (($db_error_msg = $DB->is_error())) {
	print $db_error_msg . "\n";
	exit(1);
}

$DB->query("SELECT count(*) FROM " . $DB->quote_identifier($RCI->config['db_prefix'] . 'users'));
if ($DB->is_error()) {
	// Init tables if not yet initialized
	if (!$RCI->init_db($DB)) {
		print "Failed to initialize DB";
		exit(1);
	}
}
