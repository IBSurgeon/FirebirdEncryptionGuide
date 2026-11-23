<?php
// Scenarios S1 and S7: PDO (pdo_firebird) with the client-side KeyHolder plugin and KeySource.
//
// Key transfer method C. The script has no code for the key:
//
//   * firebird.conf next to fbclient has KeyHolderPlugin = KeyHolder;
//   * the library KeySource next to fbclient returns the keys;
//   * the KeyHolder plugin of the client sends the key with the protected key exchange.
//
// PHP must load fbclient from the folder with KeySource: put that folder first in PATH.
// Create the folder with examples/common/new-keysource-client.ps1.

require __DIR__ . '/../fbcrypt_common.php';

foreach (['crypt_red', 'crypt_green', 'plain'] as $alias) {
    // An ordinary connection: no key in the script.
    echo "S7 connect to $alias: ", fbcrypt_query_note($alias), "\n";
}
