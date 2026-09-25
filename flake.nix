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
      buildToolsVersions = [ "35.0.0" ];
      platformVersions = [ "33" "34" "36" ];
      cmakeVersions = [ "3.22.1" ];

      includeCmake = true;
      includeNDK = true;
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
      ANDROID_HOME = "${comp.androidsdk}/libexec/android-sdk";
      ANDROID_SDK_ROOT = "${comp.androidsdk}/libexec/android-sdk";
      ANDROID_NDK_HOME = "${comp.androidsdk}/libexec/android-sdk/ndk/29.0.14206865";
      ANDROID_NDK_ROOT = "${comp.androidsdk}/libexec/android-sdk/ndk/29.0.14206865";
    };
  };
}
