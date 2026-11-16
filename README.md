# admute for Apple TV

An Apple TV app for [admute](https://github.com/jdogskizzle/admute). The studio's Watch tab, rebuilt for the living room: the admute channels live (ads muted,
`DELAY` behind) and the spoiler-free game recaps, driven by the Siri Remote. It talks to the
studio over the API the web Watch tab uses, so there's nothing to change on the server.

## Screens
- **Live TV**: the guide. Channels down the left (logo, what's on, how far along); the one in
  focus fills the right side: title, episode, time left, description, what's next, and
  whether an ad is being muted on it now. Click a channel to watch it. Move right to
  **Catch up** when its game has a recap.
- **Multi-view**: one channel per tuner at once (the studio's `TUNER_COUNT`, or the
  HDHomeRun's own count). Pick a main channel and side channels and start, or start it from a
  channel you're watching (**Multi-view** in the player's controls or in the guide; that
  channel becomes the main one and keeps playing without a new wait). The main channel is big
  and has the sound; when it goes to a commercial break of 15 seconds or more, the sound and
  the big spot move to a side channel that isn't in a break, and come back the moment the
  main channel's break ends. Side channels in a break are hidden (still loading, so they come
  back at once). Two layouts: **side by side** (the big channel on the left, the others in a
  column on the right, edge to edge) or **picture in picture** (the big one full screen, the
  others small in the corner). Move with the remote to select a channel; its name and a
  break countdown show on it, and fade with the outline a few seconds after the remote is
  put down. Click it to make it the main one, change it, remove it, add a channel while a
  tuner is free (also an **Add channel** spot), or switch layout. Removing the last side
  channel goes back to the normal player on the main channel, without a break in the
  picture or sound. Menu leaves. Side channels
  play at 720p to save bandwidth, the big one at full quality.
- **Recaps**: every game's recap, newest first, with *Scores & turnovers* and *All
  highlights*. A live game shows which channel it's on.
- **Settings**: the studio, the delay, sign out, and a short guide to the remote.

## Watching
The system player, so the remote behaves as it does everywhere else on Apple TV: click to
pause, Menu back to the guide, swipe down for the info panel. Added to it:

- **Channels** tab in the info panel: change channel without leaving the player.
- **Catch up** in the transport bar when the game on this channel has a recap.
- A "Tuning…" card while the studio builds up the delay, and **Ad muted** in the corner during
  a break, exactly when the picture gets there (the studio stamps each piece of the stream
  with the time, and reports breaks in the same clock).
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
1. **Xcode 26 or later** from the Mac App Store (it includes the tvOS SDK). Open it once,
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
For something that stays installed and updates itself, use TestFlight (below).

### If the build fails
- *"xcodegen: command not found"*: `brew install xcodegen`, or open a new terminal.
- *"tvOS … is not installed"* / no Apple TV simulators: Xcode > Settings > Components, install tvOS.
- *"No such module"* or files missing in Xcode: run `xcodegen generate` again.
- *"Signing for AdmuteTV requires a development team"*: only when running on a device; see
  step 5. `make build` doesn't sign.
- *"Failed to register bundle identifier"*: the ID is taken; choose another (step 5.2).
- `make clean` removes the generated project and build folder to start over.

## TestFlight
TestFlight puts the app on the Apple TV like any other app, with updates arriving by
themselves. It needs a paid [Apple Developer Program](https://developer.apple.com/programs/)
membership ($99 a year; enrolling can take a day or two).

The app has what an upload needs: the layered app icon and Top Shelf images (a placeholder
design drawn by `tools/make_icons.py`; replace the PNGs in `AdmuteTV/Assets.xcassets`, or
change the script and run `python3 tools/make_icons.py`), `ITSAppUsesNonExemptEncryption`
set so App Store Connect doesn't ask about encryption for each build, and a build number
taken from the time for every Release build (e.g. `261115.2312`), so each upload is
higher than the last without bumping anything.

### Once, at Apple
1. **Team ID**: developer.apple.com > Account > Membership details (10 characters, e.g. `A1B2C3D4E5`).
2. **Bundle ID**: developer.apple.com > Certificates, IDs & Profiles > Identifiers > **+** >
   App IDs > App. Description "admute", **Explicit** bundle ID of your own, e.g.
   `com.jdogskizzle.admute.tv`. No capabilities needed. Continue > Register.
3. **The app in App Store Connect**: appstoreconnect.apple.com > Apps > **+** > New App.
   Platform **tvOS**, a name (unique on the whole App Store, so "admute" may be taken; e.g.
   "admute TV"), language, the bundle ID from step 2, SKU `admute-tv`, Full Access.
4. **A testing group**: the app > TestFlight > Internal Testing > **+**. Name it (e.g.
   "Home"), tick **Enable automatic distribution** so every new build goes to it, and add
   yourself (anyone you add must be a user on your account: Users and Access).

### Upload from GitHub (no Mac needed after setup)
The **TestFlight** workflow (`.github/workflows/testflight.yml`) archives, signs and uploads
the app on GitHub's Macs. It signs with an App Store Connect API key, so there are no
certificates or profiles to manage.

1. **Make the API key**: App Store Connect > Users and Access > **Integrations** > App Store
   Connect API > Team Keys (the first time, **Request Access** and accept). Click **+**, name
   it "GitHub", access **Admin** (automatic signing needs to create certificates and
   profiles; App Manager isn't enough), Generate.
   - Note the **Issuer ID** (above the list) and the key's **Key ID**.
   - **Download** the key (`AuthKey_XXXXXXXXXX.p8`). Apple lets you download it once; keep it safe
     (a password manager), and revoke it here if it ever leaks.
2. **Give them to GitHub**: the repo on github.com > **Settings** > **Secrets and variables** >
   **Actions**.
   - **Secrets** tab > *New repository secret*, three times:

     | Name | Value |
     |---|---|
     | `ASC_KEY_ID` | the Key ID |
     | `ASC_ISSUER_ID` | the Issuer ID |
     | `ASC_KEY_P8` | the whole `.p8` file, opened in a text editor, including the `-----BEGIN PRIVATE KEY-----` and `-----END PRIVATE KEY-----` lines |
   - **Variables** tab > *New repository variable*, twice:

     | Name | Value |
     |---|---|
     | `APPLE_TEAM_ID` | your Team ID |
     | `BUNDLE_ID` | the bundle ID from "Once, at Apple" step 2 |

   Secrets are encrypted, hidden in logs, and only reach the workflows in this repo.
   Anyone you give write access to the repo can run them.
3. **Run it**: the **Actions** tab > **TestFlight** > **Run workflow** > Run workflow. Or tag a
   version from your computer:
   ```
   git tag v1.0.1 && git push origin v1.0.1
   ```
   It takes about 5–10 minutes. A missing secret or variable stops it at the first step
   with a message naming it.
4. **Wait for Apple**: the build appears under the app's TestFlight tab after processing
   (5–30 minutes; you get an email), and goes to your group by itself.

### Upload from your Mac instead
Put your Team ID in `DEVELOPMENT_TEAM` and your bundle ID in `PRODUCT_BUNDLE_IDENTIFIER` in
`project.yml`, run `xcodegen generate`, then in Xcode choose **Any tvOS Device (arm64)** as the
destination, **Product > Archive**, and in the Organizer **Distribute App > TestFlight
Internal Only**.

### On the Apple TV
1. Install **TestFlight** from the App Store on the Apple TV.
2. Open it and sign in with the Apple ID you added to the testing group.
3. admute is listed: **Install**. It's then on the home screen like any app; TestFlight
   installs new builds as they arrive (or click Update in TestFlight).

Builds expire after **90 days**: run the workflow again before then (TestFlight warns you).

### If the upload fails
- *"No Accounts" / "authentication" errors*: one of the three `ASC_*` secrets is wrong;
  check `ASC_KEY_P8` has the BEGIN and END lines.
- *"Cloud signing permission error" / "not allowed to create certificates"*: the key isn't
  **Admin**. Make a new one with Admin access and replace the secrets.
- *"No suitable application records were found"*: the app isn't in App Store Connect yet,
  or its bundle ID differs from `BUNDLE_ID`.
- *"SDK version issue … must be built with the tvOS 26 SDK"*: Apple wants the newest Xcode;
  the workflow picks it (`latest-stable`), and on a Mac update Xcode from the App Store.
- *"The bundle version must be higher"*: two uploads in the same minute; run it again.
- *"Your team has no devices from which to generate a provisioning profile"*: something
  asked for a development profile; the workflow avoids that by signing only for the App
  Store, at upload. Uploads from a Mac need the Apple TV paired in Xcode first.

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
| `GET api/watch/<num>/live.m3u8?keep=<a,b>` | the same, leaving the multi-view's other channels running |
| `GET api/breaks` | each open channel's ad breaks, as clock times when viewers reach them |
| `GET api/recaps`, `GET api/recap/<name>/<clip>.mp4` | recaps and their clips |
| `POST login` | sign in (form fields `username`, `password`); the session cookie comes back with the 303 |

Multi-view needs the studio from admute's "Multi-view" update; everything else works with
older ones. As with the web player, the single player plays one channel at a time and the studio lets the tuner go 20
seconds after the player closes.
