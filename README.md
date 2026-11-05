# Locus

[简体中文](README.zh-CN.md)

Free and open-source iPhone location teleport. Tap the map, search a place, or drive a route — Locus injects coordinates through Apple’s **developer location service** into `locationd`, so Maps and other apps see the spoofed GPS (not just a Wi‑Fi lookup that outdoor GPS will overwrite).

<p align="center">
  <img src="docs/screenshots/map.png" alt="Locus map with spoof pin" width="180" />
  <img src="docs/screenshots/spoofing.png" alt="Locus spoofing in 3D" width="180" />
  <img src="docs/screenshots/joystick.png" alt="Locus joystick controls" width="180" />
  <img src="docs/screenshots/route.png" alt="Locus route on map" width="180" />
</p>

## Features

- One-tap teleport (map pin or place search)
- Live joystick — walk / run / cycle / drive with light speed variation
- Walk/Drive routing on real roads & footpaths (MapKit)
- Draw a path or import / export GPX
- Background keep-alive + live status bar + drop alerts
- Favorites & recents, including named favorites from any map pin
- English and Simplified Chinese (follows the system/app language)
- Optional coordinate conversion before sending a location
- First-run setup walkthrough
- Fully on-device — no analytics, nothing uploaded

## Install

See [SETUP.md](SETUP.md) for full steps. Grab a prebuilt IPA from [Releases](https://github.com/ChrisMack32/Locus/releases), or build from source below.

Bundle ID: `com.chrismack.locus`

### LiveContainer

File pickers often don’t work inside LiveContainer. Use one of these:

1. Long-press **Locus** → **Settings** → enable **Fix File Picker**, then try Import again.
2. Share the pairing file **into LiveContainer → Locus**.
3. Copy the RPPairing plist contents → in Locus use **Paste RPPairing from clipboard** (setup or Settings).

## How it works

Locus uses the MIT-licensed [idevice](https://github.com/jkcoxson/idevice) FFI to talk to Apple’s DVT location simulation over an on-device developer tunnel (the same class of mechanism Xcode uses).

**iOS 27:** Settings → **Pair on this iPhone** advertises `_remotepairing-pairable-host._tcp`. Confirm the 6-digit code under Settings › Privacy & Security › Developer Mode › Pair with Host — no computer.

**iOS 18–26:** import an **RPPairing** file once from [idevice_pair](https://github.com/jkcoxson/idevice_pair/releases).

Use **[LocalDevVPN](https://apps.apple.com/us/app/localdevvpn/id6755608044)** or a compatible VPN such as Shadowrocket with a `10.7.0.1/32` included route. The endpoint defaults to `10.7.0.1`. LocalDevVPN is optional; see [SETUP.md](SETUP.md) for detection details.

Start a teleport on Wi‑Fi first; the session can keep working on cellular afterward.

### Pokémon GO & similar games

Locus spoofs location the same way Xcode’s developer tools do: it tells iOS “you’re here,” and other apps read that from the system. Apps that just trust GPS (Apple Maps, etc.) will follow it.

**Pokémon GO is different.** It runs its own location checks and often rejects developer / simulated GPS (e.g. “Failed to detect location”). That’s expected with this method, not a Locus bug, and there’s no supported fix for it in this app.

Tools like **iPogo** (and similar modified clients such as SpooferPro) work differently: they’re a **modified Pokémon GO app**, not a system-wide location spoof. Features live *inside* that altered game client, instead of feeding coordinates through iOS for every app. Locus never patches or replaces Pokémon GO; it only changes what the system reports. So those tools can appear to “work in Pokémon GO” while Locus correctly drives Maps but still gets blocked by Pokémon GO’s checks.

Locus is for system-level teleporting. It isn’t a Pokémon GO client or an anti-cheat bypass.

## Build

Building from source needs an Apple Developer account (free or paid) for code signing. The published IPA does **not** — just sideload it.

1. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen) if needed: `brew install xcodegen`
2. Set your **Team ID** in `project.yml` (`DEVELOPMENT_TEAM`), *or* pick your team under Xcode → Signing & Capabilities after generating the project.
3. Generate and open:

```bash
xcodegen generate
open Locus.xcodeproj
```

Or build from the CLI (replace with your Team ID from [developer.apple.com/account](https://developer.apple.com/account) → Membership):

```bash
xcodegen generate
xcodebuild -project Locus.xcodeproj -scheme Locus -configuration Release \
  -destination 'generic/platform=iOS' DEVELOPMENT_TEAM=YOUR_TEAM_ID build
```

## License

MIT. `Vendor/idevice` contains the idevice FFI (MIT). Locus is an independent open-source project and is not affiliated with Mirage / Wapixel.

## Language and map favorites

Locus follows the iOS app language. Simplified Chinese uses the standard `zh-Hans`
localization, including `zh-CN` language preferences. You can select the app language
in iOS Settings when more than one preferred language is configured.

Tap the map to drop a pin, tap the pin and choose **Save Favorite**, or use the star
above the map. Confirm a name to save it; a blank name uses the coordinates. Saved
places remain available in **Places** after relaunch. Searching retains its existing
automatic favorite behavior.

## Coordinate conversion

**Settings → Coordinate conversion** defaults to **Off**. The choices are
WGS-84 → GCJ-02, WGS-84 → BD-09, and GCJ-02 → WGS-84. Select the direction based
on the coordinate source and receiving service, not the interface language.
GPS coordinates and map-provider coordinates are not interchangeable; see
[Baidu's coordinate type documentation](https://lbsyun.baidu.com/docs/webapi?title=mapadjustment%2Furi%2Fweb).
A map pin already expressed in GCJ-02 may need the inverse conversion for a GPS
service; adding another forward offset can worsen the error.

Conversion runs once at the location engine boundary for teleports, routes, joystick
updates and resends. Pins, favorites, recents and GPX retain their original numbers.
Stop the active session before changing the setting. The offline approximation uses
longitude 72.004–137.8347 and latitude 0.8293–55.8271 as a coarse coverage rectangle,
not a precise mainland boundary; keep conversion off in other regions and border
areas. This is not an automatic MapKit datum detector or a guarantee of device accuracy.

Run the standalone coordinate checks on macOS:

```sh
xcrun swiftc -module-cache-path /tmp/locus-swift-module-cache \
  Locus/Engine/CoordinateTransform.swift Tests/CoordinateTransformChecks.swift \
  -o /tmp/locus-coordinate-checks
/tmp/locus-coordinate-checks
```

On a paired iPhone with LocalDevVPN connected, verify a recognizable map pin using
Teleport and another location app, then check Stop, joystick movement, route playback,
background resends, and a saved favorite after relaunch. Compare conversion Off and the
appropriate direction separately. A successful build or conversion check does not
verify the developer tunnel or the receiving app's location update behavior.

## Custom speed and random simulation

The speedometer beside Walk / Run / Cycle / Drive opens **Custom speed**. Set
0.1–300 km/h (default 5 km/h); the map tray and Routes share the same speed.
Save to select Custom, or Cancel to keep your current mode. Changes take effect
while moving. For Custom road routes, choose **Walking roads** or **Driving roads**
in Routes; changing speed does not rebuild an existing route.

**Settings → Random simulation** controls smooth, three-second random changes:

- Location drift is off by default, with a 3 m maximum radius (adjustable 1–100 m).
  It applies while stationary, using the joystick, and following routes, and never
  accumulates beyond the radius around the ideal location.
- Speed variation is on by default at ±10% (adjustable 0–90%). For example,
  5 km/h ±10% gives 4.5–5.5 km/h, before joystick displacement scales the speed.

Turning an option off clears its random effect at the next update. Settings and
custom speed persist after relaunch. Favorites, recents, and exported GPX keep
ideal coordinates; the spoof marker shows the location sent to the engine before
any optional coordinate conversion. Route and joystick motion stop on a location
write failure; after reconnection, start movement again explicitly.

### Build an unsigned IPA without publishing a Release

On macOS with Xcode 26.3 and XcodeGen installed:

```sh
scripts/build-unsigned-ipa.sh
```

Outputs: `outputs/Locus-unsigned.ipa`, `SHA256SUMS`, source revision/status, and
`build.log`. This runs motion/coordinate checks, regenerates the Xcode project,
archives a Release device app with `CODE_SIGNING_ALLOWED=NO`, and packages it under
`Payload/Locus.app`. It needs no signing certificate. Signing or a compatible
container is still needed to run the resulting IPA.

Alternatively, push this source to a repository you can write, open **Actions →
Build unsigned IPA (artifact) → Run workflow**, and download the artifact. It
contains the IPA and build evidence and expires after 14 days. This workflow only
needs repository read permission and does not publish a Release.

Run the standalone motion checks on Linux or macOS with Swift installed:

```sh
swiftc -module-cache-path /tmp/locus-module-cache \
  Locus/Engine/MotionModel.swift Tests/MotionChecks.swift -o /tmp/locus-motion-checks
/tmp/locus-motion-checks
```

On a paired iPhone, also check: a fixed teleport with drift on/off; full and partial
joystick displacement; road, drawn and GPX routes; editing speed during playback;
Stop and switching between modes; tunnel failure and reconnect; background and
resume. Check Chinese/English, large text and a small screen. These require a
macOS/iPhone environment and are not established by calculation checks alone.

## Developer tunnel compatibility

LocalDevVPN is optional. A compatible Shadowrocket setup can route `10.7.0.1/32`
to this device. The IP and the Remote Pairing **service port** are independent:
49152 is only the fallback, and a service restart or renewed setup can change the
actual port.

**Settings → Tunnel → Discover Remote Pairing port** defaults to on. Locus uses a
BSD socket test, tries the last confirmed port for that IP (or 49152), and discovers
`_remotepairing._tcp` on this device via Bonjour. It keeps the configured VPN IP;
nearby phones cannot supply a port unless their resolved address matches the
configured endpoint. A successful probe replaces the cached port. Manual mode
lets you enter the current **RemotePair Port** shown in SideStore's Connection
Config. Manual ports take precedence until automatic mode is enabled again.

Teleport, joystick, and route startup await discovery before native connection.
Stopping or replacing a pending start prevents it from applying a location later.
The configured/discovered port is shared by detection and the native engine.
Probes stop before native connection and while a simulation is active.

A failed TCP probe is shown as **Remote Pairing port not verified**, not proof of
a missing VPN route. Endpoint reachability still does not verify this app's pairing
or the DVT location service. Native failures report the endpoint, stage and numeric
native codes, without pairing contents. Allow Local Network access for Locus or
its container. See [SETUP.md](SETUP.md) for recovery steps and device checks.

Run the independent tunnel checks (including loopback sockets) with:

```sh
swiftc -module-cache-path /tmp/locus-module-cache -D TUNNEL_CHECKS \
  Locus/Engine/DeviceTunnel.swift Tests/TunnelChecks.swift -o /tmp/locus-tunnel-checks
/tmp/locus-tunnel-checks
```

See [GitHub build access](docs/github-build-access.md) for cloud build access.

## Route controls and connected road routes

The map tray and Routes show progress with **Pause route**, **Resume route**, and
**Stop route**. Pause retains the cursor and excludes paused time from movement;
Stop ends playback and holds the current simulated center. Replaying starts from
the prepared route's beginning. Completion also holds the endpoint. Enabled drift
continues around the held center. **End** (End spoofing) separately restores real
GPS. A location-write failure stops motion; reconnection does not resume it.

In Routes, choose **Choose stops on map**, then tap points or search places in visit
order. Finish with Done, or Undo the last stop. You can also append the selected
pin or use the current simulated/known location as the start. The numbered list
matches the map: first is start, last is destination, and the rest are intermediate
stops. Edit enables drag reordering and deletion. Adding another stop makes the
previous destination an intermediate stop.

**Build connected route** requests each leg with the selected road type, shows
progress, and supports cancellation. It commits one continuous route only after
all legs succeed; errors identify the failed leg. Shared boundary vertices are
deduplicated. Play and GPX export use the entire connected path.

Editing stops or road type invalidates that prepared road route. A running or
paused playback keeps its own snapshot; stop it before starting a new route.
Cancelled/obsolete requests cannot overwrite a newer plan. Road planning needs
Apple Maps network access. Drawn and imported GPX paths also support playback
controls, but route drafts and playback are not restored after relaunch.

The standalone motion checks now include pause/resume/stop, repeated actions,
completion, joined-leg order, distance/progress, return trips, duplicate boundaries,
and stable stop identities after reordering. On iPhone, also verify a long pause
without catch-up, hold position for more than 12 seconds after Stop route, drift
on/off, background/resume, reconnect, switching to joystick/Teleport, and ending
spoofing. Check multi-stop planning, cancellation/failure, reorder/delete and GPX
export with English/Chinese and large text.
