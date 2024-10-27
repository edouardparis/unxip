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
        ];

        # Define the enhanced extraction script with checksum verification as an argument
        extractScript = pkgs.writeShellScriptBin "unxip" ''
          #!/usr/bin/env bash
          set -euo pipefail

          if [ "$#" -ne 2 ]; then
            echo -e "Usage: unxip <path-to-xcode.xip> <outdir>"
            exit 1
          fi

          XIP_PATH="$1"
          OUT_DIR="$2"

          if [ ! -f "$XIP_PATH" ]; then
            echo -e "Error: File '$XIP_PATH' does not exist."
            exit 1
          fi

          mkdir -p "$OUT_DIR"

          echo "Extracting Xcode from $XIP_PATH..."
          ${pkgs.xar}/bin/xar -xf "$XIP_PATH" -C "$OUT_DIR"

          echo "Decompressing payload..."
          (cd "$OUT_DIR" && ${pkgs.pbzx}/bin/pbzx -n Content | ${pkgs.cpio}/bin/cpio -i)
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
