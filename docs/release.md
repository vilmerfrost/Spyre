# Release

How to ship a signed, notarized Spyre build. Nothing here is automated yet.
`scripts/build-app.sh` only makes a local, ad-hoc signed app.

## 1. Build

```sh
scripts/build-app.sh            # makes .build/app/Spyre.app
```

Before a release, set `CFBundleShortVersionString` and `CFBundleVersion` in `App/Info.plist`.

## 2. Sign with Developer ID

You need a paid Apple Developer account and a "Developer ID Application" certificate in your keychain.

```sh
codesign --force --options runtime --timestamp \
  --sign "Developer ID Application: <Name> (<TEAM_ID>)" \
  .build/app/Spyre.app
codesign --verify --strict --verbose=2 .build/app/Spyre.app
```

- `--options runtime` turns on the hardened runtime. Notarization requires it.
- `--timestamp` adds a secure timestamp. Notarization requires it.
- Spyre has no App Sandbox and no network entitlement (`SPEC.md` 8, 10). Do not add entitlements.

## 3. Notarize

Store the credentials once, in the keychain (use an app-specific password):

```sh
xcrun notarytool store-credentials spyre-notary \
  --apple-id <apple-id> --team-id <TEAM_ID> --password <app-specific-password>
```

Package, submit, and wait:

```sh
ditto -c -k --keepParent .build/app/Spyre.app .build/app/Spyre.zip
xcrun notarytool submit .build/app/Spyre.zip --keychain-profile spyre-notary --wait
```

If the status is `Invalid`, read the log: `xcrun notarytool log <submission-id> --keychain-profile spyre-notary`.

## 4. Staple

```sh
xcrun stapler staple .build/app/Spyre.app
spctl --assess --type execute --verbose .build/app/Spyre.app   # expect: accepted, Notarized Developer ID
```

For the `.dmg`: create it from the stapled app (for example with `hdiutil create`), sign the `.dmg` with the
same identity, notarize it with `notarytool submit Spyre.dmg --wait`, then `stapler staple Spyre.dmg`.

## 5. GitHub Release

Upload `Spyre-<version>.dmg` to a GitHub Release with tag `v<version>`. Get its checksum:

```sh
shasum -a 256 Spyre-<version>.dmg
```

## 6. Homebrew cask

Two options:

- **Own tap** (start here): a repo named `<owner>/homebrew-tap` (the GitHub owner of Spyre) with `Casks/spyre.rb`.
  Users run `brew install --cask <owner>/tap/spyre`. You control updates.
- **homebrew/cask** (later): open a PR to `Homebrew/homebrew-cask`. The project must meet their notability
  rules (stars, forks, age), and the app must be signed and notarized.

Cask file shape:

```ruby
cask "spyre" do
  version "0.1.0"
  sha256 "<output of shasum -a 256>"

  url "https://github.com/vilmerfrost/Spyre/releases/download/v#{version}/Spyre-#{version}.dmg"
  name "Spyre"
  desc "Menubar radar for Claude Code and Codex sessions"
  homepage "https://github.com/vilmerfrost/Spyre"

  depends_on macos: ">= :sonoma"

  app "Spyre.app"

  zap trash: "~/Library/Application Support/Spyre"
end
```

On each release, update `version` and `sha256`. Check the cask with `brew audit --cask --new spyre`
and `brew style --fix Casks/spyre.rb`.
