<?php
$DOMAINS = explode(' ', $_ENV['DOMAINS']);
define('SIMPLEID_BASE_URL', 'https://' . $DOMAINS[0]);
define('SIMPLEID_CLEAN_URL', true);
define('SIMPLEID_IDENTITIES_DIR', '/simpleid/identities');
define('SIMPLEID_CACHE_DIR', '/simpleid/cache');
define('SIMPLEID_STORE', 'filesystem');
define('SIMPLEID_STORE_DIR', '/simpleid/store');
define('SIMPLEID_ALLOW_LEGACY_LOGIN', false);
define('SIMPLEID_ALLOW_AUTOCOMPLETE', false);
define('SIMPLEID_VERIFY_RETURN_URL_USING_REALM', true);
define('SIMPLEID_DATE_TIME_FORMAT', '%Y-%m-%d %H:%M:%S %Z');
define('SIMPLEID_ASSOC_EXPIRES_IN', 3600);
define('SIMPLEID_EXTENSIONS', 'sreg,ui');
define('SIMPLEID_LOGFILE', 'php://stdout');
define('SIMPLEID_LOGLEVEL', 4);
?>
