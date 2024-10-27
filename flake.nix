{
  description = "Flake to extract Xcode SDK from a .xip file with checksum verification";

  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        # Define a custom overlay to include the 'xar' package
        customOverlay = self: super: {
          xar = self.callPackage ./xar.nix {};
        };

        overlays = [ customOverlay ];

        # Import Nix packages with the custom overlay
        pkgs = import nixpkgs { inherit system overlays; };
        lib = pkgs.lib;

        # Define the inputs for the extraction script
        extractionInputs = [
          pkgs.xar
          pkgs.cpio
          pkgs.pbzx
          pkgs.coreutils # For sha256sum
        ];

        # Define the enhanced extraction script with checksum verification as an argument
        extractScript = pkgs.writeShellScriptBin "unxip" ''
          #!/usr/bin/env bash
          set -euo pipefail

          if [ "$#" -ne 3 ]; then
            echo -e "Usage: unxip <path-to-xcode.xip> <expected-sha256-checksum> <outdir>"
            exit 1
          fi

          XIP_PATH="$1"
          EXPECTED_CHECKSUM="$2"
          OUT_DIR="$3"

          if [ ! -f "$XIP_PATH" ]; then
            echo -e "Error: File '$XIP_PATH' does not exist."
            exit 1
          fi

          echo "Computing SHA256 checksum for $XIP_PATH..."
          COMPUTED_CHECKSUM=$(${pkgs.coreutils}/bin/sha256sum "$XIP_PATH" | awk '{print $1}')

          if [ "$COMPUTED_CHECKSUM" != "$EXPECTED_CHECKSUM" ]; then
            echo -e "Error: Checksum verification failed!"
            echo -e "Expected: $EXPECTED_CHECKSUM"
            echo -e "Computed: $COMPUTED_CHECKSUM"
            exit 1
          fi

          echo -e "Checksum verification passed."

          TEMP_DIR=$(mktemp -d)
          trap "rm -rf $TEMP_DIR" EXIT

          echo "Extracting Xcode from $XIP_PATH..."
          ${pkgs.xar}/bin/xar -xf "$XIP_PATH" -C "$TEMP_DIR"

          echo "Decompressing payload..."
          (cd "$TEMP_DIR" && ${pkgs.pbzx}/bin/pbzx -n Content | ${pkgs.cpio}/bin/cpio -i)

          mkdir -p "$OUT_DIR"
          cp -r "$TEMP_DIR"/* "$OUT_DIR"
        '';

      in
        {
          packages.unxip = pkgs.stdenv.mkDerivation {
            pname = "unxip";
            version = "1.0";

            buildInputs = extractionInputs;

            unpackPhase = "true";

            installPhase = ''
              mkdir -p $out/bin
              cp ${extractScript}/bin/unxip $out/bin/
              chmod +x $out/bin/unxip
            '';

            meta = {
              description = "A tool to extract Xcode SDK from a .xip file with checksum verification";
              homepage = "https://github.com/edouardparis/unxip";
              license = lib.licenses.mit;
              maintainers = with lib.maintainers; [ edouardparis ];
            };
          };

          # Define an app for easier access
          apps = {
            unxip = {
              type = "app";
              program = "${self.packages.${system}.unxip}/bin/unxip";
              description = "Extracts Xcode SDK from a .xip file with checksum verification";
            };
          };
        }
    );
}
