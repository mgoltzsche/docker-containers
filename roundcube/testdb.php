<?php
$dbDSN = getenv('PDO_DB_DSN');
$dbUser = getenv('PDO_DB_USERNAME');
$dbPass = getenv('PDO_DB_PASSWORD');

if ($dbDSN == '' || $dbUser == '' || $dbPass == '') {
	print 'PDO_DB_DSN, PDO_DB_USERNAME or PDO_DB_PASSWORD are undefined';
	exit(1);
}

// Test if database is available
try {
	$db = new PDO($dbDSN, $dbUser, $dbPass);
	$db->query('SELECT 1');
} catch(PDOException $e) {
	$db = null;
	print "Database is not available\n";
	exit(1);
}

// TODO: init database in separate file/call
/*include '/roundcube/config/config.inc.php';
$res = $db->query('SELECT COUNT(*) FROM ' . $config['db_prefix'] . 'users');

if ($res === false) {
	print "Initializing empty database ...\n";
	$db = null;
	$_REQUEST['_step'] = 3;
	$_POST['initdb'] = true;
	set_include_path('/roundcube/installer/');
	include '/roundcube/installer/index.php';
}*/

$db = null;
