# ahrefs-task

## Usage

### Install the dependencies:
```bash
opam install --deps-only .

# In some cases, you'll need to run:
opam update && opam upgrade
```

### Build and Exec
```bash
# Build
dune build

# Run through dune
dune exec chat

# Or with the binary
./_build/default/src/chat.exe
```

### Execution Modes 

#### Server side 
```bash
dune exec chat -- --server
```

#### Client side 
```bash
dune exec chat -- --client <hostname>
# The expected hostname has the following format: 127.0.0.1:<port_number>
```
