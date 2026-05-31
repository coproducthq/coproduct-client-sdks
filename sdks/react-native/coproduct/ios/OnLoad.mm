#import <Foundation/Foundation.h>
#import "CoproductImpl.h"
#import <ReactCommon/CxxTurboModuleUtils.h>

@interface CoproductOnLoad : NSObject
@end

@implementation CoproductOnLoad

using namespace facebook::react;

+ (void)load
{
  registerCxxModuleToGlobalModuleMap(
    std::string(CoproductImpl::kModuleName),
    [](std::shared_ptr<CallInvoker> jsInvoker) {
      return std::make_shared<CoproductImpl>(jsInvoker);
    }
  );
}

@end
