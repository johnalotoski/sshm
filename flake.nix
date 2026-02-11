{
  description = "Packaging sshm (SSH Manager) using uv2nix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.uv2nix.follows = "uv2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    uv2nix = {
      url = "github:pyproject-nix/uv2nix";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    nixpkgs,
    pyproject-build-systems,
    pyproject-nix,
    uv2nix,
    ...
  }: let
    inherit (nixpkgs) lib;
    forAllSystems = lib.genAttrs lib.systems.flakeExposed;

    workspace = uv2nix.lib.workspace.loadWorkspace {workspaceRoot = ./.;};

    overlay = workspace.mkPyprojectOverlay {
      sourcePreference = "wheel";
    };

    # Suppress uv SSL_CERT_FILE warning in Nix sandbox
    suppressSslWarning = old: {
      preBuild = (old.preBuild or "") + ''
        unset SSL_CERT_FILE
      '';
    };

    # Upstream sshm uses poetry as its build backend
    buildSystemOverrides = final: prev: {
      sshm = prev.sshm.overrideAttrs (old:
        {
          nativeBuildInputs = (old.nativeBuildInputs or []) ++ [final.poetry-core];
        }
        // suppressSslWarning old);

      sshm-wrapper = prev.sshm-wrapper.overrideAttrs suppressSslWarning;
    };

    pythonSets = forAllSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in
      (pkgs.callPackage pyproject-nix.build.packages {python = pkgs.python312;}).overrideScope (
        lib.composeManyExtensions [
          pyproject-build-systems.overlays.wheel
          overlay
          buildSystemOverrides
        ]
      ));
  in {
    packages = forAllSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
      pythonSet = pythonSets.${system};
      venv = pythonSet.mkVirtualEnv "sshm-env" workspace.deps.default;

      # Wrap venv to expose only sshm binary and add shell completions
      sshm = pkgs.stdenv.mkDerivation {
        pname = "sshm";
        inherit (pythonSet.sshm) version;
        dontUnpack = true;
        nativeBuildInputs = [pkgs.installShellFiles];
        installPhase = ''
          mkdir -p $out/bin
          ln -s ${venv}/bin/sshm $out/bin/sshm

          # Generate shell completions (typer-based CLI)
          installShellCompletion --cmd sshm \
            --bash <(${venv}/bin/sshm --show-completion bash) \
            --zsh <(${venv}/bin/sshm --show-completion zsh) \
            --fish <(${venv}/bin/sshm --show-completion fish)
        '';
        meta = {
          description = "A modern command-line tool to manage SSH connections with style";
          homepage = "https://github.com/palace22/sshm";
          license = lib.licenses.gpl3Only;
          maintainers = ["johnalotoski"];
          mainProgram = "sshm";
          platforms = lib.platforms.unix;
        };
      };
    in {
      inherit sshm;
      default = sshm;
    });

    devShells = forAllSystems (system: {
      default = nixpkgs.legacyPackages.${system}.mkShell {
        packages = with nixpkgs.legacyPackages.${system}; [python312 uv];
      };
    });
  };
}
