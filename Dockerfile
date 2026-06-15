FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl git unzip xz-utils zip ca-certificates \
    openjdk-17-jdk-headless make \
    && rm -rf /var/lib/apt/lists/*

ENV ANDROID_HOME=/opt/android-sdk
ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64

# Android SDK
RUN mkdir -p $ANDROID_HOME/cmdline-tools && \
    curl -fsSL https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip -o /tmp/sdk.zip && \
    unzip -q /tmp/sdk.zip -d $ANDROID_HOME/cmdline-tools && \
    mv $ANDROID_HOME/cmdline-tools/cmdline-tools $ANDROID_HOME/cmdline-tools/latest && \
    rm /tmp/sdk.zip
RUN yes | $ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager --licenses && \
    $ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager \
    "platform-tools" "platforms;android-36" "build-tools;35.0.0"

# fvm + Flutter (version from .fvmrc baked in)
COPY .fvmrc /tmp/.fvmrc
RUN curl -fsSL https://fvm.app/install.sh | bash
ENV PATH="/root/.pub-cache/bin:/root/fvm/default/bin:/root/.fvm/bin:$PATH"
RUN FLUTTER_VERSION=$(grep -o '"[0-9][^"]*"' /tmp/.fvmrc | tr -d '"') && \
    fvm install $FLUTTER_VERSION && \
    fvm global $FLUTTER_VERSION

RUN flutter precache --android && yes | flutter doctor --android-licenses

WORKDIR /app
