#import <Foundation/Foundation.h>
#include <stdint.h>
#include <sqlite3.h>

NS_ASSUME_NONNULL_BEGIN

/// Swift cannot call SQLite's variadic connection-configuration API directly.
FOUNDATION_EXPORT int ScholiumSQLiteSetCheckpointOnClose(sqlite3 *database, BOOL enabled);

/// Keeps Apple's inode-bound NSURL intact through the native Finder operation.
/// Swift's NSURL-to-URL bridge resolves a file reference into a path URL.
FOUNDATION_EXPORT BOOL ScholiumRecycleItem(
    NSString *sourcePath,
    uint64_t expectedDevice,
    uint64_t expectedInode,
    BOOL (NS_NOESCAPE ^beforeRecycle)(void),
    NSURL * _Nullable * _Nullable resultingURL,
    NSError * _Nullable * _Nullable error
);

NS_ASSUME_NONNULL_END
