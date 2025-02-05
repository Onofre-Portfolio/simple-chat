let create () = Lwt_unix.socket Lwt_unix.PF_INET Lwt_unix.SOCK_STREAM 0

let bind address port socket =
  Lwt_unix.bind socket @@ Lwt_unix.ADDR_INET (address, port) |> ignore

let listen max_pending_requests socket =
  Lwt_unix.listen socket max_pending_requests
