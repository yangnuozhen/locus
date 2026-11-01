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

LocalDevVPN is optional. In a VPN version that supports the developer tunnel,
activate that feature and include **`10.7.0.1/32`** in its tunnel routes. Keep
Locus **Settings → Tunnel IP** at `10.7.0.1`, or use the matching custom endpoint.
A general proxy rule alone does not establish a developer service.

Locus now tests TCP reachability of the configured endpoint on port `49152`
through the system routing table. It does not require a `10.7.0.x` interface
address, LocalDevVPN installation, or a particular VPN provider. The monitor
refreshes on network changes, on return to the foreground, and every 8 seconds
while foregrounded; individual probes time out after 3 seconds. Settings also has
**Check developer tunnel**. Before a real DVT connection, Locus cancels the probe;
while a simulation service is active, it does not create extra probe connections.

**Endpoint reachable** means the port accepts a TCP connection; it does not
confirm RPPairing, the RemoteXPC handshake, or successful location injection.
Those are verified by Teleport. A missing route or unavailable service is shown
as **Developer tunnel not reachable**, never as a requirement to install
LocalDevVPN. Tapping the warning opens Locus Settings. Stop spoofing before
changing the tunnel IP.

On a paired iPhone verify LocalDevVPN, then repeat with LocalDevVPN off and a
compatible Shadowrocket `10.7.0.1/32` included route on. Check cold launch,
Settings, first-run setup, Teleport, joystick, route playback, disabling/re-enabling
the VPN, background/foreground, and a custom tunnel IP. With no compatible tunnel,
verify the warning and allow a normal Teleport attempt to report the actual error.
