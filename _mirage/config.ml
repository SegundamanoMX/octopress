open Mirage

(* If the Unix `MODE` is set, the choice of configuration changes:
   MODE=crunch (or nothing): use static filesystem via crunch
   MODE=fat: use FAT and block device (run ./make-fat-images.sh)
 *)

(* These are the default values we use when building on our dev
   environment *)
let def_address = "10.2.0.103"
let def_netmask = "255.255.255.0"
let def_gateway = "10.2.0.1"

let mode =
  try match String.lowercase (Unix.getenv "FS") with
    | "fat" -> `Fat
    | _     -> `Crunch
  with Not_found ->
    `Crunch

let fat_ro dir =
  kv_ro_of_fs (fat_of_files ~dir ())

let fs = match mode with
  | `Fat    -> fat_ro "../public"
  | `Crunch -> crunch "../public"

let net =
  try match Sys.getenv "NET" with
    | "direct" -> `Direct
    | "socket" -> `Socket
    | _        -> `Direct
  with Not_found -> `Direct

let dhcp =
  try match Sys.getenv "DHCP" with
    | "" -> false
    | _  -> true
  with Not_found -> false

let ip =
  try match Sys.getenv "IP" with
    | "" -> def_address
    | x  -> x
  with Not_found -> def_address

let nm =
  try match Sys.getenv "NETMASK" with
    | "" -> def_netmask
    | x  -> x
  with Not_found -> def_netmask

let gw =
  try match Sys.getenv "GW" with
    | "" -> def_gateway
    | x  -> x
  with Not_found -> def_gateway

let ipv4_config =  { address = Ipaddr.V4.of_string_exn ip; netmask = Ipaddr.V4.of_string_exn nm; gateways = [Ipaddr.V4.of_string_exn gw] }

let stack console =
  match net, dhcp with
  | `Direct, true  -> direct_stackv4_with_dhcp console tap0
  | `Direct, false -> direct_stackv4_with_static_ipv4 console tap0 ipv4_config
  | `Socket, _     -> socket_stackv4 console [Ipaddr.V4.any]

let server =
  conduit_direct (stack default_console)

let http_srv =
  let mode = `TCP (`Port 80) in
  http_server mode server

let main =
  foreign "Dispatch.Main" (console @-> kv_ro @-> http @-> job)

let () =
  add_to_ocamlfind_libraries ["re.str"];
  add_to_opam_packages ["re"];

  register "blog" [
    main $ default_console $ fs $ http_srv
  ]
