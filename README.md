# sshm - Nix Package

Nix flake packaging for [sshm](https://github.com/palace22/sshm), a modern command-line tool to manage SSH connections with style.

## Features

- Interactive SSH connection management (add, update, remove)
- Beautiful terminal output using Rich
- ProxyJump support for bastion hosts
- Local port forwarding
- Automatic SSH config backups
- Connection testing and searching

## Installation

### As a flake input

```nix
{
  inputs.sshm.url = "github:johnalotoski/sshm";

  outputs = { self, nixpkgs, sshm, ... }: {
    # NixOS configuration
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      modules = [
        ({ pkgs, ... }: {
          environment.systemPackages = [ sshm.packages.${pkgs.stdenv.hostPlatform.system}.default ];
        })
      ];
    };
  };
}
```

### Direct run

```bash
nix run github:johnalotoski/sshm
```

### Build locally

```bash
git clone https://github.com/johnalotoski/sshm
cd sshm
nix build
./result/bin/sshm
```

## Shell Completions

Shell completions for bash, zsh, and fish are automatically installed to the appropriate locations and will be picked up by NixOS.

## Development

Enter the development shell to update dependencies:

```bash
nix develop
uv lock
```

## Upstream

- **Upstream repository**: https://github.com/palace22/sshm
- **Author**: palace22
- **License**: GPL-3.0-only

## Packaging Notes

This package uses [uv2nix](https://github.com/pyproject-nix/uv2nix) for Python dependency management. See [NOTES.md](NOTES.md) for details on the packaging process.
