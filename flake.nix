{
  description = "Nix flake for flutter dev";

  inputs = {
    nixconfig.url = "github:sabitm/nix-config";
    nixpkgs.follows = "nixconfig/nixpkgs";
  };

  outputs = { self, nixpkgs, ... }:
  let
    system = "x86_64-linux";
    pkgs = import nixpkgs {
      inherit system;
      config = {
        allowUnfree = true;
        android_sdk.accept_license = true;
      };
    };

    libPath = with pkgs; lib.makeLibraryPath [
      libGL
      libxkbcommon
      wayland
      fontconfig
    ];

    comp = pkgs.androidenv.composeAndroidPackages {
      buildToolsVersions = [ "35.0.0" "36.0.0" ];
      platformVersions = [ "33" "34" "35" "36" ];
      cmakeVersions = [ "3.22.1" ];

      includeCmake = true;
      includeNDK = true;
      ndkVersions = [ "28.2.13676358" ];
      includeSystemImages = false;
      includeEmulator = false;
    };
  in
  {
    devShells.${system}.default = pkgs.mkShell {
      buildInputs = [
        comp.androidsdk
        pkgs.javaPackages.compiler.openjdk21
        pkgs.flutter
        pkgs.mesa-demos
      ];

      LD_LIBRARY_PATH = libPath;
      ANDROID_HOME = "$HOME/.cache/stockinfo/android-sdk";
      ANDROID_SDK_ROOT = "$HOME/.cache/stockinfo/android-sdk";
      ANDROID_NDK_HOME = "$HOME/.cache/stockinfo/android-sdk/ndk/28.2.13676358";
      ANDROID_NDK_ROOT = "$HOME/.cache/stockinfo/android-sdk/ndk/28.2.13676358";

      # Gradle and sdkmanager need a writable SDK, so stage a copy
      # in ~/.cache on first shell entry. local.properties is git-ignored.
      shellHook = ''
        NIX_SDK="${comp.androidsdk}/libexec/android-sdk"
        CACHE_SDK="$HOME/.cache/stockinfo/android-sdk"
        STAMP="$CACHE_SDK/.nix-sdk-stamp"
        if [ ! -f "$STAMP" ] || [ "$(cat "$STAMP")" != "$NIX_SDK" ]; then
          echo "Staging writable Android SDK copy..."
          rm -rf "$CACHE_SDK"
          mkdir -p "$CACHE_SDK"
          cp -r "$NIX_SDK"/. "$CACHE_SDK"/
          chmod -R u+w "$CACHE_SDK"
          echo "$NIX_SDK" > "$STAMP"
        fi
        # Flutter SDK in the Nix store is read-only and Gradle rejects
        # its plugin dir. Stage a writable copy once per Flutter version.
        NIX_FLUTTER="${pkgs.flutter}"
        CACHE_FLUTTER="$HOME/.cache/stockinfo/flutter"
        FSTAMP="$CACHE_FLUTTER/.nix-flutter-stamp"
        if [ ! -f "$FSTAMP" ] || [ "$(cat "$FSTAMP")" != "$NIX_FLUTTER" ]; then
          echo "Staging writable Flutter SDK copy..."
          rm -rf "$CACHE_FLUTTER"
          mkdir -p "$CACHE_FLUTTER"
          cp -r "$NIX_FLUTTER"/. "$CACHE_FLUTTER"/
          chmod -R u+w "$CACHE_FLUTTER"
          echo "$NIX_FLUTTER" > "$FSTAMP"
        fi
        export FLUTTER_ROOT="$CACHE_FLUTTER"
        printf 'sdk.dir=%s\nflutter.sdk=%s\n' \
          "$CACHE_SDK" "$CACHE_FLUTTER" > android/local.properties
        # The Nix SDK composition may lag behind Flutter needs.
        # Ensure licenses and NDK 28 exist in the cached copy.
        # Use the cached sdkmanager with explicit sdk_root so licenses
        # land in the writable copy, not the Nix store.
        if [ ! -d "$CACHE_SDK/ndk/28.2.13676358" ]; then
          SDKMANAGER=$(ls -d "$CACHE_SDK"/cmdline-tools/*/bin/sdkmanager 2>/dev/null | sort | tail -1)
          if [ -n "$SDKMANAGER" ]; then
            yes | "$SDKMANAGER" --sdk_root="$CACHE_SDK" --licenses > /dev/null 2>&1 || true
            "$SDKMANAGER" --sdk_root="$CACHE_SDK" "ndk;28.2.13676358" || true
          fi
        fi
        echo "Android SDK: $CACHE_SDK"
        echo "Flutter SDK: $CACHE_FLUTTER"
      '';
    };
  };
}
