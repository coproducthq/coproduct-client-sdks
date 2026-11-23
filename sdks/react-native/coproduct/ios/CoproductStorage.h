// The app directories the SDK keeps its files in. See src/NativeCoproductStorage.ts
#ifdef RCT_NEW_ARCH_ENABLED
#import "CoproductSpec.h"

@interface CoproductStorage : NSObject <NativeCoproductStorageSpec>
#else
#import <React/RCTBridgeModule.h>

@interface CoproductStorage : NSObject <RCTBridgeModule>
#endif

@end
