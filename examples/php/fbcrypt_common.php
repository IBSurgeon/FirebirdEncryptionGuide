<?php
// Helpers shared by the PHP examples.
// The examples read the connection parameters from environment variables.
// The script examples/common/setup.ps1 creates the file test-env.ps1 that sets them.

function fbcrypt_env(string $name): string
{
    $value = getenv($name);
    if ($value === false || $value === '') {
        fwrite(STDERR, "ERROR: environment variable $name is not set. " .
            "Run examples/common/setup.ps1 and dot-source test-env.ps1.\n");
        exit(2);
    }
    return $value;
}

// PDO connection string for a database alias on the test server.
function fbcrypt_dsn(string $alias): string
{
    return 'firebird:dbname=' . fbcrypt_env('FBCRYPT_HOST') . '/' . fbcrypt_env('FBCRYPT_PORT') . ':' . $alias
        . ';charset=UTF8';
}

function fbcrypt_connect(string $alias): PDO
{
    return new PDO(fbcrypt_dsn($alias), fbcrypt_env('FBCRYPT_USER'), fbcrypt_env('FBCRYPT_PASSWORD'),
        [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);
}

function fbcrypt_query_note(string $alias): string
{
    $pdo = fbcrypt_connect($alias);
    return (string) $pdo->query('select note from demo where id = 1')->fetchColumn();
}

// Reads keys from a file in KeyHolder.conf format: Key=<name> 0x..,0x..,
// Do not keep real keys in the source code. Keep them outside the web root,
// in a file that only the account of the web server can read.
function fbcrypt_read_keys(?string $path = null): array
{
    $keys = [];
    foreach (file($path ?? fbcrypt_env('FBCRYPT_KEYS'), FILE_IGNORE_NEW_LINES) as $line) {
        if (!preg_match('/^\s*Key\s*=\s*(\S+)\s+(\S+)\s*$/', $line, $m)) {
            continue;
        }
        $data = '';
        foreach (array_filter(explode(',', $m[2]), 'strlen') as $part) {
            $data .= chr(hexdec($part));
        }
        if (!in_array(strlen($data), [16, 24, 32], true)) {
            fwrite(STDERR, "ERROR: key {$m[1]} has " . strlen($data) . " bytes, need 16, 24 or 32\n");
            exit(2);
        }
        $keys[$m[1]] = $data;
    }
    return $keys;
}

// Key value in the notation of the plugin: 0x..,0x..,
function fbcrypt_key_text(string $key): string
{
    $text = '';
    foreach (str_split($key) as $byte) {
        $text .= sprintf('0x%02x,', ord($byte));
    }
    return $text;
}
