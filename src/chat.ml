type execution_mode = Server | Client | Help

let try_mode_of_string = function
  | "server" | "--server" -> Some Server
  | "client" | "--client" -> Some Client
  | "help" | "--help" -> Some Help
  | _ -> None

let print_help () =
  let help_string =
    "\n\
     Usage:\n\
    \ dune exec chat <EXECUTION_MODE>\n\n\
     Modes:\n\
    \ --server => Run as a server\n\
    \ --client => Run as a client\n\
    \ --help   => Print this menu"
  in
  print_endline help_string

let main argv =
  match argv |> Array.length with
  | 2 -> (
      match argv.(1) |> try_mode_of_string with
      | Some Server -> print_endline "Server mode"
      | Some Client -> print_endline "Client mode"
      | Some Help -> print_help ()
      | None -> print_endline "Invalid execution mode." |> print_help)
  | inputs when inputs > 2 ->
      print_endline "Too many inputs, choose only one execution mode."
      |> print_help
  | _ -> print_endline "No execution mode selected." |> print_help
;;

main Sys.argv
