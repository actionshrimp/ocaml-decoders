(** {2 Yojson implementation} *)

module Json_decodeable : Decode.Decodeable with type value = Yojson.Raw.json = struct
  type value = Yojson.Raw.json
  let pp fmt json = Format.fprintf fmt "@[%s@]" (Yojson.Raw.pretty_to_string json)

  let get_string = function
    | `Stringlit s ->
      (* Stringlits are wrapped in double-quotes. *)
      Some (String.sub s 1 (String.length s - 2))
    | _ -> None

  let get_int = function
    | `Intlit value -> Some (int_of_string value)
    | _ -> None

  let get_float = function
    | `Floatlit value -> Some (float_of_string value)
    | `Intlit value -> Some (float_of_string value)
    | _ -> None

  let get_bool = function
    | `Bool value -> Some value
    | _ -> None

  let get_null = function
    | `Null -> Some ()
    | _ -> None

  let get_list : value -> value list option = function
    | `List l -> Some l
    | _ -> None

  let get_field key = function
    | `Assoc assoc -> CCList.assoc_opt ~eq:(=) key assoc
    | _ -> None

  let get_single_field = function
    | `Assoc [(key, value)] -> Some (key, value)
    | _ -> None

  let of_string : string -> (value, string) result =
    fun string ->
      try Ok (Yojson.Raw.from_string string) with
      | Yojson.Json_error msg -> Error (msg)
end

include Decode.Make(Json_decodeable)

open Yojson.Raw

let json_of_file file =
  try Ok (from_file file) with
  | e -> Error (Decoder_error (Printexc.to_string e, None))

let keys : string list decoder =
  { run =
      function
      | `Assoc assoc -> Ok (List.map fst assoc)
      | json -> (fail "Expected an object").run json
  }

let key_value_pairs : 'a decoder -> (string * 'a) list decoder = fun decoder ->
  { run =
      function
      | `Assoc assoc ->
        assoc
        |> List.map
          CCResult.Infix.(fun (key, value_json) ->
              decoder.run value_json >|= fun value -> (key, value)
            )
        |> combine_errors
        |> CCResult.map_err
          (tag_errors (Printf.sprintf "Failed while decoding an object"))
      | json -> (fail "Expected an object").run json
  }

let key_value_pairs_seq : (string -> 'a decoder) -> 'a list decoder = fun decoder ->
  { run =
      function
      | `Assoc assoc ->
        assoc
        |> List.map (fun (key, value_json) ->
            (decoder key).run value_json
          )
        |> combine_errors
        |> CCResult.map_err
          (tag_errors (Printf.sprintf "Failed while decoding an object"))
      | json -> (fail "Expected an object").run json
  }

(* Yojson.Raw specific decoders *)

let intlit : string decoder =
  { run =
      function
      | `Intlit value -> Ok value
      | json -> (fail "Expected an int").run json
  }

let floatlit : string decoder =
  { run =
      function
      | `Floatlit value -> Ok value
      | `Intlit value -> Ok value
      | json -> (fail "Expected a float").run json
  }