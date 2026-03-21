{
  description = "Spring92 Challenge";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    nim-pkgs.url = "path:./nimpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      nim-pkgs,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
      in
      {
        packages.default = pkgs.stdenv.mkDerivation {
          pname = "spring92";
          version = "0.0.1";
          src = ./.;

          buildInputs = with pkgs; [
            nim-2_0
            sqlite
            openssl
            imagemagick
          ];
          nativeBuildInputs = with pkgs; [ makeWrapper ];

          buildPhase = ''
            mkdir -p $out/bin

            # Setup nim package path
            export HOME=$(pwd)
            export PATH=$PATH:${pkgs.imagemagick}/bin
            mkdir -p packages

            for pkg in ${nim-pkgs.packages.${system}.default}/pkgs/*; do
              # Copy package to local packages directory
              if [ -d $pkg ]; then
                cp -r $pkg packages/
              else
                cp $pkg packages/
              fi
            done

            cd src && ${pkgs.nim-2_0}/bin/nim c -d:release -d:ssl --mm:none --path:../packages -o:$out/bin/app main.nim
          '';

          postInstall = ''
            wrapProgram $out/bin/app \
              --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.imagemagick ]}
          '';
        };

        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            nim-2_0
            sqlite
            openssl
            imagemagick
          ];
          shellHook = ''
            # Set up nim package path from nimpkgs flake
            if [ ! -d packages ] || [ -z "$(ls -A packages 2>/dev/null)" ]; then
              echo "Setting up Nim packages..."
              mkdir -p packages
              for pkg in ${nim-pkgs.packages.${system}.default}/pkgs/*; do
                if [ -d "$pkg" ]; then
                  cp -r "$pkg" packages/
                else
                  cp "$pkg" packages/
                fi
              done
            fi

            dev-build() {
              (cd src && nim c -d:ssl --mm:none --path:../packages -o:../app main.nim)
            }

            dev-run() {
              dev-build && ./app
            }

            echo "Spring92 dev shell"
            echo "  dev-build  — compile the app"
            echo "  dev-run    — compile and run (static files served live from ./static/)"
          '';
        };
      }
    );
}
