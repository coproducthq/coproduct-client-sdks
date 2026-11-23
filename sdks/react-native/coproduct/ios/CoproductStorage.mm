#import "CoproductStorage.h"

#import <Foundation/Foundation.h>

// The app's directory of the given kind. NSSearchPathForDirectoriesInDomains
// always returns the sandbox path on iOS, and these are the same directories
// react-native-fs reported, so files written by earlier releases are found
static NSString *CoproductDirectoryPath(NSSearchPathDirectory directory) {
    return NSSearchPathForDirectoriesInDomains(directory, NSUserDomainMask, YES).firstObject ?: @"";
}

// The path of a file directly inside the documents directory, or nil when the
// name is not a bare file name
static NSString *CoproductDocumentFilePath(NSString *name) {
    if (name.length == 0 || [name containsString:@"/"] || [name isEqualToString:@".."] || [name isEqualToString:@"."]) {
        return nil;
    }
    return [CoproductDirectoryPath(NSDocumentDirectory) stringByAppendingPathComponent:name];
}

@implementation CoproductStorage
RCT_EXPORT_MODULE()

#ifdef RCT_NEW_ARCH_ENABLED

- (NSString *)cachesDirectoryPath {
    return CoproductDirectoryPath(NSCachesDirectory);
}

- (NSString * _Nullable)readDocumentFile:(NSString *)name {
    NSString *path = CoproductDocumentFilePath(name);
    return path == nil ? nil : [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
}

// Atomic, so a crash mid-write leaves the previous contents rather than a
// truncated file
- (NSNumber *)writeDocumentFile:(NSString *)name contents:(NSString *)contents {
    NSString *path = CoproductDocumentFilePath(name);
    if (path == nil) {
        return @NO;
    }
    [[NSFileManager defaultManager] createDirectoryAtPath:CoproductDirectoryPath(NSDocumentDirectory) withIntermediateDirectories:YES attributes:nil error:nil];
    return @([contents writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil]);
}

- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:
    (const facebook::react::ObjCTurboModule::InitParams &)params
{
    return std::make_shared<facebook::react::NativeCoproductStorageSpecJSI>(params);
}
#endif

@end
