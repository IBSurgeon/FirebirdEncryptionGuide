<?php
// Scenario S6: encrypted backup and restore from a script.
//
// Firebird 4.0 and 5.0: gbak -KeyHolder KeyHolderStdin, the key goes to the standard input of gbak.
// Firebird 3.0: gbak has no -KeyHolder switch. The script writes the key to a temporary file
// that only the current user can read, and runs gbak -KEYFILE.
//
// The key is never put on the command line: other users can see the command line.

require __DIR__ . '/../fbcrypt_common.php';

const KEY_NAME = 'Red';
const MARKER = 'Hello from crypt_red';

// Runs gbak. The line with the key goes to the standard input of the process.
// Returns [exit code, error text].
function run_gbak(array $args, ?string $keyLine): array
{
    $gbak = fbcrypt_env('FBCRYPT_CLIENT') . (PHP_OS_FAMILY === 'Windows' ? '/gbak.exe' : '/bin/gbak');
    $command = array_merge([$gbak, '-user', fbcrypt_env('FBCRYPT_USER'), '-password', fbcrypt_env('FBCRYPT_PASSWORD')], $args);

    // An array command: PHP starts the program without a shell.
    $process = proc_open($command, [0 => ['pipe', 'r'], 1 => ['pipe', 'w'], 2 => ['pipe', 'w']], $pipes);
    if ($process === false) {
        return [-1, "cannot start $gbak"];
    }
    if ($keyLine !== null) {
        fwrite($pipes[0], $keyLine);
    }
    fclose($pipes[0]);
    $errors = stream_get_contents($pipes[2]);
    stream_get_contents($pipes[1]);
    fclose($pipes[1]);
    fclose($pipes[2]);
    return [proc_close($process), $errors];
}

function gbak_with_key(array $args, string $key, int $fbMajor): array
{
    $keyLine = 'Key=' . KEY_NAME . ' ' . fbcrypt_key_text($key);
    if ($fbMajor >= 4) {
        return run_gbak(array_merge($args, ['-keyholder', 'KeyHolderStdin']), $keyLine);
    }

    // Firebird 3.0: a temporary key file. tempnam creates it with access for the owner only.
    $keyFile = tempnam(sys_get_temp_dir(), 'fbkey');
    try {
        file_put_contents($keyFile, $keyLine . "\n");
        return run_gbak(array_merge($args, ['-keyfile', $keyFile, '-keyname', KEY_NAME]), null);
    } finally {
        unlink($keyFile);
    }
}

function report(string $title, array $result, bool $mustFail = false): bool
{
    [$exitCode, $errors] = $result;
    $failed = $exitCode !== 0;
    if ($failed === $mustFail) {
        echo "$title: ", $mustFail ? 'error, as expected' : 'OK', "\n";
    } else {
        echo "$title: ", $mustFail ? 'NO ERROR - this is wrong' : 'FAILED', "\n";
    }
    if ($failed) {
        fwrite(STDERR, "--- $title\n$errors\n");
    }
    return $failed === $mustFail;
}

$fbMajor = (int) (getenv('FBCRYPT_FB_MAJOR') ?: 5);
$key = fbcrypt_read_keys()[KEY_NAME];
$work = fbcrypt_env('FBCRYPT_WORK');
$backupFile = $work . DIRECTORY_SEPARATOR . 'tmp' . DIRECTORY_SEPARATOR . 'php-crypt_red.fbk';
$restoredDb = $work . DIRECTORY_SEPARATOR . 'db' . DIRECTORY_SEPARATOR . 'php-restored.fdb';
$server = fbcrypt_env('FBCRYPT_HOST') . '/' . fbcrypt_env('FBCRYPT_PORT') . ':';

try {
    // 1. Backup without a key must fail: the database is encrypted.
    report('Backup without a key', run_gbak(['-b', $server . 'crypt_red', $backupFile], null), true);

    // 2. Backup with the key. The backup file is encrypted too.
    if (!report('Backup with the key', gbak_with_key(['-b', $server . 'crypt_red', $backupFile], $key, $fbMajor))) {
        exit(1);
    }
    $encrypted = strpos(file_get_contents($backupFile), MARKER) === false;
    echo 'Backup file is encrypted: ', $encrypted ? 'yes' : 'NO - this is wrong', "\n";

    // 3. Restore without a key must fail: gbak cannot read the encrypted backup file.
    report('Restore without a key', run_gbak(['-rep', $backupFile, $server . $restoredDb], null), true);

    // 4. Restore with the key. gbak encrypts the new database with the same key.
    report('Restore with the key', gbak_with_key(['-rep', $backupFile, $server . $restoredDb], $key, $fbMajor));
} finally {
    @unlink($backupFile);
    @unlink($restoredDb);
}
