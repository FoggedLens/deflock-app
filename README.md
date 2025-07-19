# Flock Map App (Stage 1)

A minimal Flutter scaffold for mapping and tagging Flock‑style ALPR cameras in OpenStreetMap.

# NOTE:
Forks should register for their own oauth2 client id from OSM: https://www.openstreetmap.org/oauth2/applications
These are hardcoded in lib/services/auth_service.dart for each app.
If you discover a bug that causes bad behavior w/rt OSM API, you might want to register a new one for the patched version to distinguish them. You can also then delete the old version from OSM to prevent new people from using the old version.


## Platform setup notes
### iOS
Add location permission strings to `ios/Runner/Info.plist`:
```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>This app needs your location to show nearby cameras.</string>
```


## Stuff for build env
# Install from GUI:
Xcode, Android Studio.
Xcode cmdline tools
Android cmdline tools + NDK

# Terminal
brew install openjdk@17
sudo ln -sfn /usr/local/opt/openjdk@17/libexec/openjdk.jdk /Library/Java/JavaVirtualMachines/openjdk.jdk

brew install ruby

gem install cocoapods

sdkmanager --install "ndk;27.0.12077973"

export PATH="/Users/bob/.gem/ruby/3.4.0/bin:$PATH"

export PATH=$HOME/development/flutter/bin:$PATH

flutter clean
flutter pub get
flutter run
