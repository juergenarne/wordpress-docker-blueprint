<?php
/**
 * The base configuration for WordPress
 *
 * The wp-config.php creation script uses this file during the installation.
 * You don't have to use the website, you can copy this file to "wp-config.php"
 * and fill in the values.
 *
 * This file contains the following configurations:
 *
 * * Database settings
 * * Secret keys
 * * Database table prefix
 * * ABSPATH
 *
 * @link https://developer.wordpress.org/advanced-administration/wordpress/wp-config/
 *
 * @package WordPress
 */

// ** Database settings - You can get this info from your web host ** //
/** The name of the database for WordPress */
// define( 'DB_NAME', 'wordpress' );
define( 'DB_NAME', getenv('WORDPRESS_DB_NAME') ?: 'wordpress' );

/** Database username */
// define( 'DB_USER', 'wordpress' );
define( 'DB_USER', getenv('WORDPRESS_DB_USER') ?: 'wordpress' );

/** Database password */
// define( 'DB_PASSWORD', 'password' );
define( 'DB_PASSWORD', getenv('WORDPRESS_DB_PASSWORD') ?: 'password' );

/** Database hostname */
// define( 'DB_HOST', 'db:3306' );
define( 'DB_HOST', getenv('WORDPRESS_DB_HOST') ?: 'db:3306' );

/** Database charset to use in creating database tables. */
define( 'DB_CHARSET', 'utf8' );

/** The database collate type. Don't change this if in doubt. */
define( 'DB_COLLATE', '' );

/**#@+
 * Authentication unique keys and salts.
 *
 * Change these to different unique phrases! You can generate these using
 * the {@link https://api.wordpress.org/secret-key/1.1/salt/ WordPress.org secret-key service}.
 *
 * You can change these at any point in time to invalidate all existing cookies.
 * This will force all users to have to log in again.
 *
 * @since 2.6.0
 */
define( 'AUTH_KEY',         'r|:wU`XQ[=|zZ(L~4UlG+O<csxB>/.fuKa:gS-2ae/kA<X7kznjV6.JY0R%Z!kVp' );
define( 'SECURE_AUTH_KEY',  'eh@dFL_G5dYTeKoz9Y%-:lFM6]Uq1PzmHOnJQa6;FbU;D{uU&Qh$D3I_^&R0rkso' );
define( 'LOGGED_IN_KEY',    'zC1e.F&YznO@W2H|KzNx>=o.C5-`9HcXMvX2APkPL1~QMWs|{k~*PqzN8BI5%`$&T' );
define( 'NONCE_KEY',        'M&V(dW2G~A!y$S]zKbxW`|T!Hw;A4K^X7n3NxR!aQ^A,F(=Tq?5Z$.y7!XHG>#P7' );
define( 'AUTH_SALT',        'P#Q_N&t}9.{?StfZ1<Q}4(J!7;Jf5+q2Qx7bRsm>DBXEe+t?oeMW&-5tUPN8{,Xo' );
define( 'SECURE_AUTH_SALT', 'KrXjM8%jXH3zKc`Nb<@Za$|Xr=sE8AhNE`mYGeW#U)#qvAGL<d9KEZ3:bJ8rWvLD' );
define( 'LOGGED_IN_SALT',   'L|Z$Q6+wBoZ6+@xf3_Hq(3iPY)VhEVS2b@t^F@Swb?U4Z^;eCw6:AHne}Wm7T%(_' );
define( 'NONCE_SALT',       '8n_?AM)fXt&mvU|h`3TW{GtSEf|4AHc[;@#M^mT-2zktE|Fy^Kmbnd+YGJ.AHpmQ' );

/**#@-*/

/**
 * WordPress database table prefix.
 *
 * You can have multiple installations in one database if you give each
 * a unique prefix. Only numbers, letters, and underscores please!
 */
$table_prefix = 'wpy_';

/**
 * For developers: WordPress debugging mode.
 *
 * Change this to true to enable the display of notices during development.
 * It is strongly recommended that plugin and theme developers use WP_DEBUG
 * in their development environments.
 *
 * For information on other constants that can be used for debugging,
 * visit the documentation.
 *
 * @link https://developer.wordpress.org/advanced-administration/debug/debug-wordpress/
 */
define( 'WP_DEBUG', false );

/* Add any custom values between this line and the "stop editing" line. */
define( 'WP_REDIS_HOST', (getenv('WORDPRESS_APP_NAME') ?: 'wordpress') . '-redis' ); // Container-Name
define( 'WP_REDIS_PORT', getenv('WORDPRESS_REDIS_PORT') ?: '6379' );
define( 'WP_REDIS_TIMEOUT', 1 );
define( 'WP_REDIS_READ_TIMEOUT', 1 );
define( 'WP_REDIS_DATABASE', 0 );

define( 'WP_ALLOW_MULTISITE', true );
/* That's all, stop editing! Happy publishing. */

/** Absolute path to the WordPress directory. */
if ( ! defined( 'ABSPATH' ) ) {
	define( 'ABSPATH', __DIR__ . '/' );
}

/** Sets up WordPress vars and included files. */
require_once ABSPATH . 'wp-settings.php';
