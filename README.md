# ahrefs-task

## Usage

### Install the dependencies:
```bash
opam install --deps-only .

# Troubleshooting
# Problems related to missing package or No agreement on the version of ocaml might require:
opam update && opam upgrade
```

### Build and Exec
```bash
dune build

dune exec chat
```
