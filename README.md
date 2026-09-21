# pyinit

Bash script that scaffolds a new Python project: venv, src/ (or flat) layout,
.gitignore, optional deps. Linux/macOS only, needs python3 on PATH.

## Usage

    ./pyinit [--name NAME] [--path PATH] [--deps "dep1 dep2 ..."] [--flat]

- `--name`   folder to create (optional, defaults to current dir)
- `--path`   where to operate (optional, defaults to `.`, must already exist)
- `--deps`   space-separated packages to install (optional)
- `--flat`   skip the src/ layout

## Example

    ./pyinit --name myapp --deps "flask requests"

## Install (so it runs as `pyinit` from anywhere)

    chmod +x pyinit
    mv pyinit /opt/homebrew/bin/pyinit   # or wherever's on $PATH

## Tests

    ./test_pyinit.sh
