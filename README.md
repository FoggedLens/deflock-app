# Flock Map App (Stage 1)

A minimal Flutter scaffold for mapping and tagging Flock‑style ALPR cameras in OpenStreetMap.

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
