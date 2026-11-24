// KeyChecker: a library that the KeyHolder plugin calls for each key it loads.
//
// The plugin looks for the library with the name KeyChecker in the folder of Firebird
// libraries (Windows: next to firebird.exe or fbclient.dll; Linux: the lib folder).
// The library must export the function CheckKey.
//
// The function gets the key name, the full path of the current program, and a pointer
// to the key value. It returns nothing, so it cannot reject a key. It can:
//   * write an audit record (this example);
//   * change the key value in place. The length cannot change.
//
// This example writes one line for each key to the file from the environment variable
// FBCRYPT_KEYCHECKER_LOG. It never writes the key value.
//
// Build (Windows, Visual C++):  cl /LD /EHsc /O2 KeyChecker.cpp /Fe:KeyChecker.dll
// Build (Linux):                g++ -shared -fPIC -O2 -o libKeyChecker.so KeyChecker.cpp

#include <cstdio>
#include <cstdlib>
#include <ctime>

#ifdef _WIN32
#define DLL_EXPORT __declspec(dllexport)
#else
#define DLL_EXPORT __attribute__((visibility("default")))
#endif

extern "C" DLL_EXPORT void CheckKey(const char* keyName, const char* exeName, unsigned keyLen, void* keyValue)
{
    (void) keyValue;    // the example does not read and does not change the key

    const char* logName = std::getenv("FBCRYPT_KEYCHECKER_LOG");
    if (!logName || !logName[0])
        return;

    FILE* log = std::fopen(logName, "a");
    if (!log)
        return;

    char stamp[32] = "";
    std::time_t now = std::time(nullptr);
    std::strftime(stamp, sizeof(stamp), "%Y-%m-%d %H:%M:%S", std::localtime(&now));

    std::fprintf(log, "%s key=%s length=%u program=%s\n", stamp, keyName, keyLen, exeName);
    std::fclose(log);
}
