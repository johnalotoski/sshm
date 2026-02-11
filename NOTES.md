# sshm Nix Packaging Notes

## Goal
Package [sshm](https://github.com/palace22/sshm) (SSH Manager CLI) using uv2nix instead of poetry2nix.

## Solution Summary

Successfully packaged sshm using uv2nix with a wrapper package approach.

### Key Files
- `flake.nix` - uv2nix based flake
- `pyproject.toml` - Wrapper package that pulls sshm from git
- `uv.lock` - Generated lock file
- `sshm_wrapper/__init__.py` - Minimal package for hatchling

### Usage
```bash
# Build
nix build

# Run
./result/bin/sshm

# Update lock file
nix develop -c uv lock
```

### Features
- Shell completions for bash, zsh, and fish (installed to `share/` for NixOS auto-discovery)
- Only exposes `sshm` binary (not python, typer, etc.)
- Suppresses uv SSL_CERT_FILE warnings for main packages

## Previous Approach (poetry2nix) - Failed
- Used `poetry2nix.mkPoetryApplication`
- Failed with PyNaCl wheel 404 error - the wheel version in poetry.lock is no longer available on PyPI

## Issues Resolved During Development

### 1. PyNaCl wheel 404 (poetry2nix)
**Solution**: Switched to uv2nix which resolved to PyNaCl 1.6.2.

### 2. Missing poetry.core module
**Solution**: Added override in flake.nix to include poetry-core in nativeBuildInputs for sshm.

### 3. Hatchling direct reference error
**Solution**: Added `[tool.hatch.metadata] allow-direct-references = true`

### 4. Missing README.md
**Solution**: Removed `readme = "README.md"` from pyproject.toml

### 5. Hatchling can't find files to include
**Solution**: Created minimal `sshm_wrapper/__init__.py` and set `packages = ["sshm_wrapper"]`

### 6. Typer/Click compatibility error
**Cause**: uv resolved click to 8.3.1 but sshm requires `click >=8.0.0,<8.2.0`
**Solution**: Added explicit click constraint in pyproject.toml dependencies.

### 7. SSL_CERT_FILE warnings during build
**Cause**: Nix sandbox sets invalid SSL_CERT_FILE path
**Solution**: Added `unset SSL_CERT_FILE` in preBuild for sshm and sshm-wrapper packages.

### 8. Polluted bin directory
**Cause**: Copying entire venv exposed python, typer, etc.
**Solution**: Only symlink `sshm` binary from the venv.

## Resources
- [uv2nix Getting Started](https://pyproject-nix.github.io/uv2nix/usage/getting-started.html)
- [uv2nix GitHub](https://github.com/pyproject-nix/uv2nix)
- [pyproject-nix](https://github.com/pyproject-nix/pyproject.nix)
