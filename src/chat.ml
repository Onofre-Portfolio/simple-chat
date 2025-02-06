open Server
open Client
open Cmdliner

let server_cmd =
  let doc = "Run as a server side." in
  let workflow = fun () -> () |> start_server |> Lwt_main.run in
  let term = Term.(const workflow $ const ()) in
  let info = Cmd.info "server" ~doc in
  Cmd.v info term

let client_cmd =
  let hostname_conv =
    let parse s =
      let is_valid_inet_addr =
        try
          Unix.inet_addr_of_string s |> ignore;
          true
        with _ -> false
      in
      if is_valid_inet_addr then Ok s else Error (`Msg "Invalid hostname.")
    in
    Arg.conv (parse, Format.pp_print_string)
  in
  let hostname_arg =
    let doc = "Server hostname required for establish a connection." in
    Arg.(
      required
      & opt (some hostname_conv) None
      & info [ "h"; "hostname" ] ~docv:"<HOSTNAME>" ~doc)
  in
  let port_number_conv =
    let parse s =
      let is_valid_port, port =
        try
          int_of_string s |> ignore;
          (true, port)
        with _ -> (false, 0)
      in
      if is_valid_port then Ok port
      else Error (`Msg "Unable to parse the port number.")
    in
    Arg.conv (parse, Format.pp_print_int)
  in
  let port_number_arg =
    let doc = "Port number where the server is listening." in
    Arg.(
      required
      & opt (some port_number_conv) None
      & info [ "p"; "port" ] ~docv:"<PORT_NUMBER>" ~doc)
  in
  let doc = "Run as a client side." in
  let workflow _hostname _port =
    start_client "127.0.0.1" 8090 |> Lwt_main.run
  in
  let term = Term.(const workflow $ hostname_arg $ port_number_arg) in
  let info = Cmd.info "client" ~doc ~man:[] in
  Cmd.v info term

let main_cmd =
  let doc = "A simple one on one chat." in
  let info = Cmd.info "chat" ~version:"0.0.1" ~doc in
  (*let default = Term.(const print_help $ const ()) in*)
  let default = Term.(ret (const (`Help (`Pager, None)))) in
  Cmd.group info ~default [ server_cmd; client_cmd ]

let () = exit @@ Cmd.eval main_cmd
