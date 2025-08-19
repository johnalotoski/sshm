{
  description = "Standalone flake for packaging sshm via poetry2nix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    flake-utils.url = "github:numtide/flake-utils";
    poetry2nix.url = "github:nix-community/poetry2nix";
    treefmt-nix.url = "github:numtide/treefmt-nix";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    poetry2nix,
    treefmt-nix,
  }:
    flake-utils.lib.eachDefaultSystem (system: let
      cargoShim = final: prev: {
        rustPlatform =
          prev.rustPlatform
          // {
            fetchCargoTarball = args: let
              # Prefer explicit `hash`, else fall back to legacy `sha256`
              h =
                if args ? hash
                then args.hash
                else if args ? sha256
                then args.sha256
                else throw "rustPlatform.fetchCargoTarball shim: missing `hash`/`sha256`";
              cleaned = builtins.removeAttrs (args // {hash = h;}) ["sha256"];
            in
              prev.rustPlatform.fetchCargoVendor cleaned;
          };
      };

      pkgs = import nixpkgs {
        inherit system;
        overlays = [
          poetry2nix.overlays.default
          cargoShim
        ];
      };

      p2n = pkgs.poetry2nix;
      python = pkgs.python312;

      sshmSrc = pkgs.fetchFromGitHub {
        owner = "palace22";
        repo = "sshm";
        rev = "7e6443c303448913beaaa08888d3074d0d170a9d";
        sha256 = "sha256-w6LxCPz2zMWyfrTvzT0Db9uzyoROshtUSaFdBxMWd6E=";
      };

      sshmApp = p2n.mkPoetryApplication {
        projectDir = sshmSrc;
        preferWheels = true;

        overrides = p2n.overrides.withoutDefaults (self: super: let
          bcryptVersion = "4.2.0";

          bcryptSdist = python.pkgs.fetchPypi {
            pname = "bcrypt";
            version = bcryptVersion;
            hash = "sha256-z2nq9Rhf1Y8mj4BbUFzjH5ufwtZLN2ZCFk6SRFQMEiE=";
          };

          bcryptRepo = pkgs.fetchFromGitHub {
            owner = "pyca";
            repo = "bcrypt";
            rev = "4.2.0";
            hash = "sha256-UyBXF+x7ouigsQ7HvKdUZnIMcU9HwDYvtW+BxjasPfY=";
          };
        in {
          inherit
            (python.pkgs)
            annotated-types
            black
            click
            iniconfig
            isort
            markdown-it-py
            mypy
            paramiko
            pathspec
            pyyaml
            shellingham
            ;

          typing_extensions =
            if self ? "typing-extensions"
            then self."typing-extensions"
            else super.typing_extensions;

          bcrypt = let
            cargoVendor = pkgs.rustPlatform.fetchCargoVendor {
              pname = "bcrypt";
              version = bcryptVersion;

              # The repo contains src/_bcrypt/Cargo.lock
              src = bcryptRepo;

              # Important for pyca/bcrypt layout
              cargoRoot = "src/_bcrypt";
              hash = "sha256-TD1Qacr2BS3CutGzDcUSweTrlMuKy0U/eIS/oBLxTlI=";
            };
          in
            python.pkgs.buildPythonPackage {
              pname = "bcrypt";
              version = bcryptVersion;
              src = bcryptSdist;

              # PEP 517 build (setuptools-rust), not legacy setuptools
              pyproject = true;
              nativeBuildInputs = [
                pkgs.rustc
                pkgs.cargo
                pkgs.pkg-config
                python.pkgs.setuptools-rust
                python.pkgs.setuptools
                python.pkgs.wheel
              ];

              # Create a local Cargo config that replaces crates.io with the vendored tree
              postPatch = ''
                  mkdir -p .cargo
                  cat > .cargo/config.toml <<EOF
                [source.crates-io]
                replace-with = "vendored-sources"

                [registries.crates-io]
                protocol = "sparse"

                [source.vendored-sources]
                directory = "${cargoVendor}"
                EOF
              '';

              # Make sure Cargo stays offline
              preBuild = ''
                export CARGO_NET_OFFLINE=true
              '';

              # Still attach cargoDeps so Nix tracks the vendor tree as an input
              cargoRoot = "src/_bcrypt";
              cargoDeps = cargoVendor;

              doCheck = false;
              pythonImportsCheck = ["bcrypt"];
            };

          # Packaging uses pyproject/flit (no setup.py)
          packaging = python.pkgs.buildPythonPackage rec {
            pname = "packaging";
            version = "24.2";
            src = python.pkgs.fetchPypi {
              inherit pname version;
              hash = "sha256-wiim3F6TLTRrxXOTeRCdSeiFPdgiNXHHxbVSYO3AuX8=";
            };
            pyproject = true;
            nativeBuildInputs = [python.pkgs.flit-core];
            doCheck = false;
            pythonImportsCheck = ["packaging"];
          };

          pre-commit = python.pkgs.toPythonModule pkgs.pre-commit;

          typer = python.pkgs.buildPythonPackage rec {
            pname = "typer";
            version = "0.12.5";
            src = python.pkgs.fetchPypi {
              inherit pname version;
              hash = "sha256-9ZLwib7cyOwbl0El1khRApw7GvFF8ErKZNaUEPDJtyI=";
            };
            pyproject = true;
            nativeBuildInputs = [python.pkgs.pdm-backend];
            propagatedBuildInputs = with self; [
              click
              rich
              shellingham
              typing-extensions
            ];
            doCheck = false;
            pythonImportsCheck = ["typer"];
          };
        });
      };

      sshm = sshmApp.overrideAttrs (old: {
        nativeBuildInputs = (old.nativeBuildInputs or []) ++ [pkgs.installShellFiles];

        postInstall =
          (old.postInstall or "")
          + ''
            if [ -x "$out/bin/sshm" ]; then
              installShellCompletion --cmd sshm --bash <($out/bin/sshm --show-completion bash)
            fi
          '';
      });

      treefmtEval = treefmt-nix.lib.evalModule pkgs {
        projectRootFile = "flake.nix";
        programs.alejandra.enable = true;
      };
    in {
      packages = {
        inherit sshm;
        default = sshm;
      };

      devShells.default = pkgs.mkShell {
        packages = with pkgs; [
          alejandra
          icdiff
          treefmtEval.config.package
          sshm
        ];

        shellHook = ''
          if ! [ -f treefmt.toml ]; then
            echo "Copying treefmt.toml"
            cp -f ${treefmtEval.config.build.configFile} treefmt.toml
          else
            if ! $(cmp -s ${treefmtEval.config.build.configFile} treefmt.toml); then
              echo "Re-copying treefmt.toml for an update.  The difference between old and new treefmt.toml is:"
              icdiff treefmt.toml ${treefmtEval.config.build.configFile}
              cp -f ${treefmtEval.config.build.configFile} treefmt.toml
            else
              echo "treefmt.toml is up to date"
            fi
          fi
        '';
      };
    });
}
