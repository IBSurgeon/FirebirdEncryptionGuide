<?php
// Scenarios S1, S2 and S3: PDO (pdo_firebird) with the fbcrypt library through FFI.
//
// Key transfer method E: pdo_firebird works on the ISC API, and fbcrypt registers
// the key callback for the current thread. The key exchange is protected.
// The server does not need UnsafeClient = true.
//
// Conditions:
//   * the FFI extension is on (ffi.enable = true);
//   * PHP loads fbclient from the client folder of the plugin: put that folder first in PATH.
//     fbcrypt_init must get the path of the same fbclient.
//
// Standard output is the same on each run (see expected-output.txt).
// Full error texts go to standard error.

require __DIR__ . '/../fbcrypt_common.php';

$client = fbcrypt_env('FBCRYPT_CLIENT');
$windows = PHP_OS_FAMILY === 'Windows';
$fbcryptLibrary = $client . ($windows ? '/fbcrypt.dll' : '/lib/libfbcrypt.so');
$fbclientLibrary = $client . ($windows ? '/fbclient.dll' : '/lib/libfbclient.so');

// "const char* data": the value is binary, the length goes in the third argument.
$fbcrypt = FFI::cdef('
    int fbcrypt_init(const char* clientPathName);
    int fbcrypt_key(const char* name, const char* data, unsigned int dl);
    int fbcrypt_callback(void* provider);
', $fbcryptLibrary);

function check(int $rc, string $function): void
{
    if ($rc < 0) {
        fwrite(STDERR, "ERROR: $function = $rc\n");
        exit(1);
    }
}

function add_key(FFI $fbcrypt, string $name, string $key): void
{
    check($fbcrypt->fbcrypt_key($name, $key, strlen($key)), 'fbcrypt_key');
}

function expect_error(string $title, string $alias): void
{
    try {
        fbcrypt_query_note($alias);
        echo "$title: NO ERROR - this is wrong\n";
    } catch (PDOException $e) {
        echo "$title: error, as expected\n";
        fwrite(STDERR, "--- $title\n" . $e->getMessage() . "\n\n");
    }
}

$keys = fbcrypt_read_keys();

check($fbcrypt->fbcrypt_init($fbclientLibrary), 'fbcrypt_init');
// The callback is registered for the current thread. One call is enough for a PHP process
// that is not thread-safe (CLI, php-fpm).
check($fbcrypt->fbcrypt_callback(null), 'fbcrypt_callback');

// S1: one key
add_key($fbcrypt, 'Red', $keys['Red']);
echo 'S1 connect with key Red: ', fbcrypt_query_note('crypt_red'), "\n";

// S3: two keys in the list, two databases
add_key($fbcrypt, 'Green', $keys['Green']);
echo 'S3 two keys, database crypt_red: ', fbcrypt_query_note('crypt_red'), "\n";
echo 'S3 two keys, database crypt_green: ', fbcrypt_query_note('crypt_green'), "\n";

// S2: errors. fbcrypt_init(NULL) clears the key list.
$fbcrypt->fbcrypt_init(null);
expect_error('S2 no key', 'crypt_red');
add_key($fbcrypt, 'Red', $keys['Green']);
expect_error('S2 wrong key value', 'crypt_red');
$fbcrypt->fbcrypt_init(null);
add_key($fbcrypt, 'Blue', $keys['Red']);
expect_error('S2 wrong key name', 'crypt_red');

// Back to the right key
$fbcrypt->fbcrypt_init(null);
add_key($fbcrypt, 'Red', $keys['Red']);
echo 'S1 connect again with key Red: ', fbcrypt_query_note('crypt_red'), "\n";
