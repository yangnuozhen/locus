# Locus — install & first teleport

## 1. Sideload the IPA

Install the latest IPA from [Releases](https://github.com/ChrisMack32/Locus/releases) (or build from source) with Feather, SideStore, AltStore, Sideloadly, or LiveContainer.

Bundle ID: `com.chrismack.locus`

### LiveContainer

File pickers often break inside LiveContainer. Do one of the following:

1. Long-press **Locus** in LiveContainer → **Settings** → enable **Fix File Picker**, then try Import again.
2. Share / open the pairing file **into LiveContainer → Locus** (iOS share sheet).
3. Copy the RPPairing plist contents, open Locus → **Paste RPPairing from clipboard** (setup or Settings).

## 2. Pairing

### On iOS 27 — no computer

1. Open Locus → **Settings → Pair on this iPhone** → **Start pairing**.
2. Allow **Local Network** (and Location / Notifications if asked).
3. Leave Locus open. Go to **Settings › Privacy & Security › Developer Mode › Pair with Host**.
4. Pick **Locus** → **Pair**.
5. Enter your **iPhone unlock passcode** first (authorizes pairing).
6. When the second prompt appears, type the **6-digit code** Locus shows (also sent as a notification).
7. Done — RPPairing file is saved on-device.

### On iOS 18–26

1. On a computer, download [idevice_pair](https://github.com/jkcoxson/idevice_pair/releases).
2. Plug in your iPhone, unlock, Trust.
3. Generate an **RPPairing** file (not lockdown / SideStore `.mobiledevicepairing`).
4. AirDrop / Share → Open in **Locus**, **Import**, or **Paste from clipboard**.

## 3. Developer tunnel

Use [LocalDevVPN](https://apps.apple.com/us/app/localdevvpn/id6755608044), or a compatible VPN such as Shadowrocket with a `10.7.0.1/32` included tunnel route (default endpoint `10.7.0.1`). See the compatibility notes below.

## 4. Teleport

On Wi‑Fi: drop a pin → **Teleport**. Then joystick / routes / GPX work; the session can continue on cellular.

### Shadowrocket and other compatible VPNs

LocalDevVPN is optional. Enable a compatible developer tunnel and include the
`10.7.0.1/32` route. Keep Locus's tunnel IP at `10.7.0.1` unless you use a custom
endpoint. A route and a Remote Pairing service port are separate settings.

Leave **Discover Remote Pairing port** enabled. Locus tries its per-IP last
confirmed port (initial fallback 49152), then resolves this device's
`_remotepairing._tcp` Bonjour service and checks candidate ports with BSD sockets.
Discovery filters out nearby services unless their address belongs to this device
or matches the configured target. It does not change the IP or VPN configuration.
Startup waits up to 8 seconds for preflight; each TCP candidate has a 2-second
budget and Bonjour browsing has a 3-second budget. An existing native simulation
skips port discovery. Preflight and native connection use the same selected port.

If discovery fails, inspect **SideStore → Connection Config → RemotePair Port**
(the effective/discovered port, not an empty override field). Turn automatic port
discovery off in Locus, enter that port, and save. Manual mode remains fixed until
you enable automatic discovery again. Allow Local Network permission for Locus or
its container; a denied Bonjour request does not prove a route is missing.

**Remote Pairing port not verified** is an advisory result. Teleport still attempts
the actual native connection. Its error identifies the endpoint, stage and numeric
native code/sub-code, never pairing contents. Locus's imported RPPairing file must
also be valid; SideStore's success alone does not establish that. Stop spoofing
before changing endpoint settings. You can cancel a pending connection with End.

On iPhone verify automatic discovery with a non-49152 service port, manual mode,
service/port changes, foreground/background, stop during discovery, permission
denial, and a custom IP. Then verify Teleport, joystick, route playback and a
native pairing failure. A failed discovery must not show a fabricated connected
state or overwrite a newer request. Return numeric error codes if a correct port
still cannot create the DVT location service.
