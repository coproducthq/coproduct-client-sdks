## Unreleased

Flag observations are now ordered and carry their value from the moment they are
created: registering an observer delivers the current value first, converging to
later values in revision order. When the host is still processing an update,
intermediate transitions may be coalesced to the latest state. A key that has no
usable value reports the caller's default rather than being skipped. Cancel an
observation by calling `cancel()` on the handle the registration returned.
