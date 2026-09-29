# Automatic attributes in detail

The SDK sets ten attributes on the device with no code from you. The README's
[Automatic attributes](../README.md#automatic-attributes) section lists them
with their values. This page covers how each one is worked out and when it is
left unset.

An attribute that is **unset** has no value at all. A rule condition that needs
it to have a value does not match, and an `is_not_set` condition on it does.
The SDK leaves an attribute unset rather than guess a value that may be wrong.

## Contents

- [When the attributes are read](#when-the-attributes-are-read)
- [What startupTimeout does not bound](#what-startuptimeout-does-not-bound)
- [platform, os_version, app_version, and app_build](#platform-os_version-app_version-and-app_build)
- [locale and timezone](#locale-and-timezone)
- [device_type](#device_type)
- [network_type](#network_type)
- [first_seen_at and session_count](#first_seen_at-and-session_count)
- [When first_seen_at and session_count are unset](#when-first_seen_at-and-session_count-are-unset)
- [Location attributes from Coproduct](#location-attributes-from-coproduct)

## When the attributes are read

Every attribute except `network_type` is read once, when `initialize` runs,
and does not change until the SDK is shut down and initialized again.
`first_seen_at` and `session_count` do not change for the rest of the launch.
`network_type` is live.

`initialize` waits for the attributes it reads, within `startupTimeout`. Most
are ready well before that. One whose source is slower applies as soon as it
arrives, and observations and `CoproductFlagBuilder` update when it does. In a
debug build the console shows `coproduct: automatic attribute "<name>" was not
available when initialize returned` both for a late attribute and for one the
device has no value for. If a rule depends on one of these
attributes, prefer `CoproductFlagBuilder` or an observation over a single read
taken straight after `initialize`.

If you set an attribute with the same name as an automatic one, your value is
the one rules see while it is set. Remove yours with `removeAttributes` and
the automatic value applies again.

## What startupTimeout does not bound

`startupTimeout` limits how long `initialize` waits for the first download and
the automatic attributes. `initialize` can still take slightly longer, because
some work is not bounded by it:

- Loading the SDK's native library and opening the saved flags. These count
  against the limit, but `initialize` waits for them however long they take.
- Applying the automatic attributes collected so far, which happens after the
  limit passes.

Work the limit cuts short carries on in the background:

- A first download that has not finished keeps going, for up to
  `requestTimeout`, and its flags apply when it lands.
- An automatic attribute that was not ready applies when it arrives.

## platform, os_version, app_version, and app_build

- **`platform`** is `"ios"` or `"android"`.
- **`os_version`** is the operating system version, such as iOS `17.4` or
  Android `14`.
- **`app_version`** is your app's version name: `CFBundleShortVersionString`
  on iOS and `versionName` on Android. In a Flutter app these come from the
  part of `version:` in `pubspec.yaml` before the `+`.
- **`app_build`** is your app's build number: `CFBundleVersion` on iOS and
  `versionCode` on Android, the part of `version:` after the `+`. It is a
  string, not a number.

`os_version` and `app_version` are normalized to three numeric parts, so they
compare correctly with version operators:

| Reported | Stored as |
|---|---|
| `17.4` | `17.4.0` |
| `14` | `14.0.0` |
| `v2.3` | `2.3.0` |
| `1.2.3.4` | `1.2.3` |
| `2.0-beta` | `2.0-beta`, unchanged, because it is not a plain dotted number |

A value that is not a plain dotted number is kept as it is, so a rule can
still match it with the string operators.

## locale and timezone

- **`locale`** is the device's primary locale from the system settings, as a
  language tag such as `"en-US"`. It is not the locale your app selected with
  `MaterialApp.locale` or similar. An underscore separator is changed to a
  hyphen, so `en_US` becomes `en-US`.
- **`timezone`** is the device's time zone as an IANA name, such as
  `"Europe/London"`.

A device that changes its language or time zone while your app runs keeps the
old value until the SDK is shut down and initialized again.

## device_type

`device_type` is `"phone"` or `"tablet"`. It is **left unset rather than
guessed** on a device that is neither.

**On iOS** it comes from the interface idiom the system reports:

| Interface idiom | `device_type` |
|---|---|
| Phone | `"phone"` |
| Pad | `"tablet"` |
| Anything else | Unset |

An iPhone or iPad app running on a Mac with Apple silicon, or on Apple Vision
Pro, can report the iPad idiom. It is then classified `"tablet"`.

**On Android** there is no equivalent system property, so Coproduct classifies
the device by its smallest screen width, using the 600dp threshold of
Android's own `sw600dp` layout qualifier. This is Coproduct's policy, not
something the operating system reports.

| Device | `device_type` |
|---|---|
| Smallest width under 600dp | `"phone"` |
| Smallest width 600dp or more | `"tablet"` |
| Televisions, watches, cars, appliances, and VR headsets | Unset |
| Chromebooks and Android PCs | Unset |

A foldable is classified from its posture when the SDK starts, and is not
reclassified when it folds or unfolds. If that matters to you, write rules
that tolerate either value.

On both platforms `device_type` is also unset when the SDK's native plugin
does not respond, which the SDK reports as `HostContextUnavailable`.

## network_type

`network_type` is how the device is connected right now:

| Value | Meaning |
|---|---|
| `"wifi"` | Wi-Fi |
| `"cellular"` | A mobile data network |
| `"ethernet"` | A wired connection |
| `"other"` | Connected some other way, such as Bluetooth or USB tethering or satellite |
| `"none"` | No connection |

- **It is live.** It changes when the connection does, and observations update
  with it.
- **It has no value until its first reading**, which usually arrives during
  or shortly after initialization. `initialize` never waits for it.
- **It describes the connection, not whether the internet is reachable.** A
  Wi-Fi network behind a sign-in page is still `"wifi"`.
- **Behind a VPN**, Android 9 and later usually reports the connection
  underneath. When the system cannot say which connection the VPN uses, the
  value is `"other"`, as it always is on Android 7.0 to 8.1.
- **If the SDK loses its connection to the system's network updates**, it
  keeps retrying and meanwhile keeps the last value it saw. For a while it can
  describe a connection the device has since left.

On Android the SDK declares the `ACCESS_NETWORK_STATE` permission to read the
connection type. It merges into your app's manifest, is granted at install,
and never prompts.

## first_seen_at and session_count

- **`first_seen_at`** is when the SDK first ran in this installation of your
  app, in whole seconds since the Unix epoch, UTC.
- **`session_count`** is how many app launches have initialized the SDK,
  counting this one. It starts at 1.

Both are numbers, so target them with `gte`, `lt`, and the other numeric
operators.

### What counts as a launch

One process launch counts once. These do not add to the count:

- a hot restart;
- a second `FlutterEngine`;
- shutting the SDK down and initializing it again;
- backgrounding and resuming the app.

A launch after the system has ended your app's process does count. Every
`FlutterEngine` in one launch sees the same two values, and they do not change
during the launch, even if the stored record is removed.

The count is approximate by design. An Android app that runs in several
processes may count each of them, and a process killed immediately after
launch may not be counted.

### How long they last

Both belong to the app installation. Every SDK key and environment your app
uses sees the same values. They stay on the device, in `UserDefaults` on iOS
and a private `SharedPreferences` file on Android. They are kept apart from the
native iOS SDK's values if your app uses both.

They normally reset when the app's data is removed. They may survive a device
migration or a backup restore, as other app data can.

## When first_seen_at and session_count are unset

Both are left unset for a launch in which the device cannot give the SDK a
trustworthy record, rather than restarting the count. The SDK then reports
`SessionAttributesUnavailable` through `FlutterError.onError`, and the values
return on a later launch that can read the record.

On iOS this includes:

- a launch before the device is first unlocked after a restart, such as a
  background launch straight after a reboot;
- a launch in which the system reports no stored record while one is still on
  disk;
- every launch while the device is locked, if your app's default data
  protection class is complete.

On Android this includes a launch in which the storage cannot be opened. That
can happen when your app runs before the first unlock after a restart, as a
direct-boot-aware app can.

Both are also unset when the SDK's native plugin does not respond, which the
SDK reports as `HostContextUnavailable`.

## Location attributes from Coproduct

Beyond the ten automatic attributes, Coproduct supplies location attributes
with your flags: `country`, `continent`, `region_code`, and `city`. Coproduct
derives them from the IP address of the device's request for flags.

- They are approximate, and any of them can be absent, for example behind a
  VPN or a satellite connection.
- `country`, `continent`, and `region_code` are uppercase. `region_code` is
  the subdivision code without the country prefix, such as `"TX"`.
- They have the lowest precedence. An automatic attribute or one you set with
  the same name overrides them. The device's own `timezone` takes precedence
  over the time zone Coproduct derives.
- They update when the SDK downloads new flags, and are saved with the flags
  between launches.
