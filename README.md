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
- [x] The wire protocol should not make any assumptions about the message contents (e.g., allowed byte values, character encoding, etc.).


## Installing and Building

### Install the dependencies:
```bash
$ opam install --deps-only .

# In some cases, you'll need to run:
$ opam update && opam upgrade
```

### Build and Exec
```bash
# Build
$ dune build

# Run through dune
$ dune exec chat

# Or with the binary
$ ./_build/default/src/chat.exe
```

## Usage
### Execution Modes 

#### Server side 
```bash
$ dune exec chat -- server
```
Expected output:

```bash
Starting server...
Listening on 127.0.0.1:8090.
```

#### Client side 
```bash
$ dune exec chat -- client --hostname <hostname> --port <port_number>
```
Expected output (if there is a server running and you passed the correct hostname + port number):

```bash
$ dune exec chat -- client --hostname localhost --port 8090
Connected to 127.0.0.1:8090
```

#### Guide
* The `hostname` is expected to be a ip value such as `127.0.0.1` or a host like `localhost`.
* Any `host` added to `/etc/hosts` should work fine.
* In case of the host isnt on `/etc/hosts` or an invalid ip, this should be the expected behaviour:
```bash
chat: option '--hostname': Invalid hostname.
Usage: chat client [--hostname=<HOSTNAME>] [--port=<PORT_NUMBER>] [OPTION]…
Try 'chat client --help' or 'chat --help' for more information.
```
* Something similar goes to the port number:
```bash
$ dune exec chat -- client --hostname localhost --port notanumber
chat: option '--port': Unable to parse the port number.
Usage: chat client [--hostname=<HOSTNAME>] [--port=<PORT_NUMBER>] [OPTION]…
Try 'chat client --help' or 'chat --help' for more information.
```

