#include "CoproductImpl.h"
#include "react-native-coproduct.h"

namespace facebook::react {

CoproductImpl::CoproductImpl(
  std::shared_ptr<CallInvoker> jsInvoker
)
  : NativeCoproductCxxSpec(jsInvoker), jsInvoker_(std::move(jsInvoker)) {}

bool CoproductImpl::installRustCrate(jsi::Runtime& rt) {
  return coproduct::installRustCrate(rt, jsInvoker_) != 0;
}

bool CoproductImpl::cleanupRustCrate(jsi::Runtime& rt) {
  return coproduct::cleanupRustCrate(rt) != 0;
}

}
