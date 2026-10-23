# Kingmakers RP launcher (Android)

The app players open first: character name, server list with live status, Discord link, and
the Play button. It's your own app (`com.kingmakers.rp`), contains no game files, and can be
shared or published freely.

- **Live status** uses the SA-MP / open.mp query protocol (UDP, game port): server name,
  players, ping, and the Discord invite open.mp servers publish.
- **Name rule** is the same as the server's (`Firstname_Lastname`).
- **Play** checks for the official GTA: San Andreas (`com.rockstargames.gtasa`). Without it,
  the player is sent to its Google Play page. With it, the launcher says the mobile client is
  still being finished and offers the address for PC players. Once the mobile client is done,
  this button will start it.

## Build

Needs JDK 17+ and the Android SDK (`local.properties` with `sdk.dir=...`, or `ANDROID_HOME`).

```
./gradlew assembleDebug -Pkingmakers.serverHost=YOUR.SERVER.IP
```

The APK is `app/build/outputs/apk/debug/app-debug.apk`. `kingmakers.serverName/Host/Port` in
`gradle.properties` set the default server; players can add more in the app.

## Tests

```
./gradlew testDebugUnitTest                         # query protocol, name rule, UI flow
./gradlew testDebugUnitTest -PscreenshotDir=shots   # also saves shots/launcher.png
```

The query tests run against a local responder that answers the way open.mp's
`Query::handleQuery` does; the UI test runs the real activity under Robolectric.
