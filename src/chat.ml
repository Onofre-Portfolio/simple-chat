open Simple_chat
open Cmdliner

let is_valid_inet_addr input : bool * string =
  try
    let host_entry = Unix.gethostbyname input in
    let first_address = host_entry.h_addr_list.(0) in
    let ip = Unix.string_of_inet_addr first_address in
    (true, ip)
  with _ -> (false, "")

let is_valid_port input =
  try
    let port = int_of_string input in
    (true, port)
  with _ -> (false, 0)

let server_cmd =
  let port_number_conv =
    let parse s =
      let is_valid, port = is_valid_port s in
      if is_valid then Ok port
      else Error (`Msg "Unable to parse the port number.")
    in
    Arg.conv (parse, Format.pp_print_int)
  in
  let port_number_arg =
    let doc = "Server port number." in
    Arg.(
      value
      & opt (some port_number_conv) None
      & info [ "p"; "port" ] ~docv:"<PORT_NUMBER>" ~doc)
  in
  let doc = "Run as a server side." in
  let workflow = fun port_opt -> port_opt |> Server.start |> Lwt_main.run in
  let term = Term.(const workflow $ port_number_arg) in
  let info = Cmd.info "server" ~doc in
  Cmd.v info term

let client_cmd =
  let hostname_conv =
    let parse s =
      let is_valid, ip = is_valid_inet_addr s in
      if is_valid then Ok ip else Error (`Msg "Invalid hostname.")
    in
    Arg.conv (parse, Format.pp_print_string)
  in
  let hostname_arg =
    let doc = "Server address required for establish a connection." in
    Arg.(
      required
      & opt (some hostname_conv) None
      & info [ "h"; "hostname" ] ~docv:"<HOSTNAME>" ~doc)
  in
  let port_number_conv =
    let parse s =
      let is_valid, port = is_valid_port s in
      if is_valid then Ok port
      else Error (`Msg "Unable to parse the port number.")
    in
    Arg.conv (parse, Format.pp_print_int)
  in
  let port_number_arg =
    let doc = "Server port number." in
    Arg.(
      required
      & opt (some port_number_conv) None
      & info [ "p"; "port" ] ~docv:"<PORT_NUMBER>" ~doc)
  in
  let doc = "Run as a client side." in
  let workflow hostname port = Client.start hostname port |> Lwt_main.run in
  let term = Term.(const workflow $ hostname_arg $ port_number_arg) in
  let info = Cmd.info "client" ~doc ~man:[] in
  Cmd.v info term

let main_cmd =
  let doc = "A simple one on one chat." in
  let info = Cmd.info "chat" ~version:"0.0.1" ~doc in
  let default = Term.(ret (const (`Help (`Pager, None)))) in
  Cmd.group info ~default [ server_cmd; client_cmd ]

let () = exit @@ Cmd.eval main_cmd
