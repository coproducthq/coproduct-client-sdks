#pragma once

#include <CoproductSpecJSI.h>

#include <memory>

namespace facebook::react {

class CoproductImpl
  : public NativeCoproductCxxSpec<CoproductImpl> {
public:
  CoproductImpl(std::shared_ptr<CallInvoker> jsInvoker);

  bool installRustCrate(jsi::Runtime& rt);
  bool cleanupRustCrate(jsi::Runtime& rt);

private:
  std::shared_ptr<CallInvoker> jsInvoker_;
};

}
