# Versions, download addresses and ports of the example.
# Firebird archives: the SHA-256 value is fixed. Change it together with the version.
# Plugin archives: IBSurgeon replaces them every month (new trial license), so there is no fixed SHA-256.
@{
    Firebird = @{
        '3' = @{
            Version  = '3.0.14.33856'
            Url      = 'https://github.com/FirebirdSQL/firebird/releases/download/v3.0.14/Firebird-3.0.14.33856-0-x64.zip'
            Sha256   = 'a070bc5633f9fb5ad261d87d19276324679e8ec77afb03a2bec056ba7e2d2dad'
            Provider = 'Engine12'
            Port     = 30053
        }
        '4' = @{
            Version  = '4.0.7.3271'
            Url      = 'https://github.com/FirebirdSQL/firebird/releases/download/v4.0.7/Firebird-4.0.7.3271-0-x64.zip'
            Sha256   = 'd1ccbff156750ea712635dc49b3a1405fd1c9f23a952b018c885e7ba6af59d06'
            Provider = 'Engine13'
            Port     = 30054
        }
        '5' = @{
            Version  = '5.0.4.1812'
            Url      = 'https://github.com/FirebirdSQL/firebird/releases/download/v5.0.4/Firebird-5.0.4.1812-0-windows-x64.zip'
            Sha256   = '01e844fce4d5f53272a76205dbc3a1ba4b782ab8e8eadcd808cdbccd9ce13b72'
            Provider = 'Engine13'
            Port     = 30055
        }
    }
    Plugin = @{
        '3' = @{
            Url    = 'https://cc.ib-aid.com/download/distr/crypt/CryptPlugin-FB_30_WINDOWS_64bit.zip'
            Folder = 'FB_30_WINDOWS_64bit'
        }
        '4' = @{
            Url    = 'https://cc.ib-aid.com/download/distr/crypt/CryptPlugin-FB_40_WINDOWS_64bit.zip'
            Folder = 'FB_40_WINDOWS_64bit'
        }
        '5' = @{
            Url    = 'https://cc.ib-aid.com/download/distr/crypt/CryptPlugin-FB_50_WINDOWS_64bit.zip'
            Folder = 'FB_50_WINDOWS_64bit'
        }
    }
}
