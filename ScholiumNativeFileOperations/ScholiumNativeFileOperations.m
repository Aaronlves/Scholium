#import "ScholiumNativeFileOperations.h"
#import <AppKit/AppKit.h>
#include <sys/stat.h>

int ScholiumSQLiteSetCheckpointOnClose(sqlite3 *database, BOOL enabled) {
    return sqlite3_db_config(database, SQLITE_DBCONFIG_NO_CKPT_ON_CLOSE, enabled ? 0 : 1, NULL);
}

BOOL ScholiumRecycleItem(
    NSString *sourcePath,
    uint64_t expectedDevice,
    uint64_t expectedInode,
    BOOL (^beforeRecycle)(void),
    NSURL **resultingURL,
    NSError **error
) {
    if (resultingURL) *resultingURL = nil;
    if (error) *error = nil;
    NSURL *pathURL = [NSURL fileURLWithPath:sourcePath];
    NSURL *reference = pathURL.fileReferenceURL;
    struct stat status;
    if (!reference || !reference.isFileReferenceURL ||
        lstat(reference.fileSystemRepresentation, &status) != 0 ||
        (uint64_t)status.st_dev != expectedDevice ||
        (uint64_t)status.st_ino != expectedInode) {
        if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain
            code:NSFileReadUnknownError userInfo:@{
                NSLocalizedDescriptionKey: @"The native Trash file reference no longer identifies the confirmed source."
            }];
        return NO;
    }
    if (!beforeRecycle()) return NO;

    dispatch_semaphore_t completion = dispatch_semaphore_create(0);
    __block NSURL *destination = nil;
    __block NSError *operationError = nil;
    // Apple's completion callback runs on the active requesting queue.
    // Keep that queue free while the descriptor-owning caller waits.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [NSWorkspace.sharedWorkspace recycleURLs:@[reference]
            completionHandler:^(NSDictionary<NSURL *, NSURL *> *newURLs, NSError *nativeError) {
                destination = newURLs[reference];
                operationError = nativeError;
                dispatch_semaphore_signal(completion);
            }];
    });
    dispatch_semaphore_wait(completion, DISPATCH_TIME_FOREVER);
    if (resultingURL) *resultingURL = destination;
    if (error) *error = operationError;
    return destination != nil;
}
