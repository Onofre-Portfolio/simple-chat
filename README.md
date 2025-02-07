# Test task for Ahrefs
## About 

I must develop a simple chat application with the following requirements:
- [x] A client mode.
- [x] A server mode.
- [x] The server should wait for and listen to incoming connections.
- [x] The client should take the server's hostname to connect to.
- [x] After the connection is established, both parties should be able to send messages.
- [x] The server should continue listening for connections after one is closed.
- [x] The acknowledgment message should be `Message received`.
- [x] The receiving side should always return the acknowledgment message.
- [x] The sending side should always calculate the round-trip time for the acknowledgment message.
- [ ] The wire protocol should not make any assumptions about the message contents (e.g., allowed byte values, character encoding, etc.).


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
