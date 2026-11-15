# admute for Apple TV

An Apple TV app for [admute](https://github.com/jdogskizzle/admute). The studio's Watch tab, rebuilt for the living room: the admute channels live (ads muted,
`DELAY` behind) and the spoiler-free game recaps, driven by the Siri Remote. It talks to the
studio over the API the web Watch tab uses, so there's nothing to change on the server.

## Screens
- **Live TV**: the guide. Channels down the left (logo, what's on, how far along); the one in
  focus fills the right side: title, episode, time left, description, what's next, and
  whether an ad is being muted on it now. Click a channel to watch it. Move right to
  **Catch up** when its game has a recap.
- **Recaps**: every game's recap, newest first, with *Scores & turnovers* and *All
  highlights*. A live game shows which channel it's on.
- **Settings**: the studio, the delay, sign out, and a short guide to the remote.

## Watching
The system player, so the remote behaves as it does everywhere else on Apple TV: click to
pause, Menu back to the guide, swipe down for the info panel. Added to it:

- **Channels** tab in the info panel: change channel without leaving the player.
- **Catch up** in the transport bar when the game on this channel has a recap.
- A "Tuning…" card while the studio builds up the delay, and **Ad muted** in the corner during
  a muted break (timed to when the picture gets there, not when the proxy mutes it).
- A TV remote's **channel up/down** buttons (through HDMI-CEC) change channel.
- **Captions**: the broadcast's closed captions, if the player finds them in the stream
  (swipe down, Subtitles).

During a recap, clips play one after another and plays added in the meantime are picked up.
As in the web player, nothing gives a play away early: a card shows the set-up at the start of
each play ("CHI ball · 3rd & 8 at CHI 44", the score before) and the result only in its last
seconds. The **Plays** tab lists results only for plays already watched. The transport bar has
*Previous play*, *Next play* and *Back to live*; the channel buttons skip plays too. While
a live game's recap plays, the app keeps its channel loading, so going back to live at the end
is immediate.

## Compiling

You need a Mac; tvOS apps can only be built with Xcode.

### 1. Install the tools (once)
1. **Xcode 15 or later** from the Mac App Store (it includes the tvOS SDK). Open it once,
   accept the licence and let it install its components. If it asks which platforms to
   download, tick **tvOS** (or later: Xcode > Settings > Components > tvOS).
2. Point the command-line tools at it:
   ```
   sudo xcode-select -s /Applications/Xcode.app
   xcodebuild -version
   ```
3. **Homebrew** (https://brew.sh), then **XcodeGen**, which makes the Xcode project from
   `project.yml` (the `.xcodeproj` isn't kept in the repo):
   ```
   brew install xcodegen
   ```

### 2. Get the code and make the project
```
git clone https://github.com/jdogskizzle/Admute-tv.git
cd Admute-tv
xcodegen generate          # writes AdmuteTV.xcodeproj and AdmuteTV/Info.plist
```
Run `xcodegen generate` again after pulling changes that add or remove files or touch
`project.yml`.

### 3. Check it compiles (no signing, no Apple TV needed)
```
make build
```
which runs
```
xcodebuild -project AdmuteTV.xcodeproj -scheme AdmuteTV -configuration Debug \
  -destination 'generic/platform=tvOS Simulator' CODE_SIGNING_ALLOWED=NO build
```
It ends with `** BUILD SUCCEEDED **`. The same build runs on GitHub Actions for every push
(`.github/workflows/build.yml`).

### 4. Run it in the simulator
`make open` (or `open AdmuteTV.xcodeproj`), pick an **Apple TV** simulator in the toolbar's
device menu and press **Run** (⌘R). The simulator's remote: arrow keys to move, Return to
click, Esc for Menu; or Window > Show Apple TV Remote. From the terminal,
`make sim` builds, installs and starts it on the "Apple TV 4K (3rd generation)" simulator
(`make sim SIM="Apple TV"` for another one; `xcrun simctl list devices` lists them).

The simulator has to reach your studio, so use an address the Mac can open in a browser.

### 5. Run it on your Apple TV
1. In Xcode, select the **AdmuteTV** target > **Signing & Capabilities**: tick *Automatically
   manage signing* and choose your **Team** (sign in to your Apple ID under Xcode > Settings >
   Accounts; a free account works, a paid developer account keeps the app installed longer).
   To keep it across `xcodegen generate`, put your team ID in `DEVELOPMENT_TEAM` in
   `project.yml`.
2. Change the **Bundle Identifier** from `com.example.admute.tv` to one of your own
   (e.g. `com.yourname.admute.tv`), in `project.yml` (`PRODUCT_BUNDLE_IDENTIFIER`) or in Xcode.
3. Pair the Apple TV: on the TV, Settings > Remotes and Devices > Remote App and Devices
   (the Mac and the TV on the same network). In Xcode, Window > Devices and Simulators: the
   Apple TV shows up; click **Pair** and type the code shown on the TV.
4. Pick the Apple TV in the device menu and press **Run**. The first run takes a while as
   Xcode prepares the device.

With a free Apple ID the app stops opening after 7 days; run it from Xcode again to renew.
A paid account lasts a year, or put it on TestFlight.

### If the build fails
- *"xcodegen: command not found"*: `brew install xcodegen`, or open a new terminal.
- *"tvOS … is not installed"* / no Apple TV simulators: Xcode > Settings > Components, install tvOS.
- *"No such module"* or files missing in Xcode: run `xcodegen generate` again.
- *"Signing for AdmuteTV requires a development team"*: only when running on a device; see
  step 5. `make build` doesn't sign.
- *"Failed to register bundle identifier"*: the ID is taken; choose another (step 5.2).
- `make clean` removes the generated project and build folder to start over.

## Signing in
On first start it asks for the studio's address (the one you open it at in a browser, e.g.
`home.example.com/admute`; `https://` is assumed when no scheme is given) and its username and
password. Typing works with the on-screen keyboard or from an iPhone. It signs in through the
studio's normal sign-in (formlogin) and keeps only the session cookie, in the Keychain. The
password isn't saved. The session lasts 30 days. Changing the password in the studio signs
the Apple TV out, as it does every other device. If the studio has sign-in turned off
(`STUDIO_AUTH=off`), it connects with just the address.

Plain-HTTP addresses are allowed (App Transport Security is relaxed in `project.yml`), since
the studio and the guide's channel logos are often on the home network.

## What it uses from the studio
| | |
|---|---|
| `GET api/channels` | channels, now/next from the guide, and whether each is muting an ad |
| `GET api/watch/<num>/live.m3u8` | the channel as HLS (two versions, 1080p/720p and 720p 5 Mb/s) |
| `GET api/recaps`, `GET api/recap/<name>/<clip>.mp4` | recaps and their clips |
| `POST login` | sign in (form fields `username`, `password`); the session cookie comes back with the 303 |

As with the web player, one channel plays at a time and the studio lets the tuner go 20
seconds after the player closes.
