(*
 * Copyright (C) 2006-2009 Citrix Systems Inc.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published
 * by the Free Software Foundation; version 2.1 only. with the special
 * exception on linking described in file LICENSE.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *)
module D = Debug.Make(struct let name="bios_strings" end)
open D
open Stdext.Xstringext

let dmidecode_prog = "/usr/sbin/dmidecode"

let remove_invisible str =
  let l = String.split_on_char '\n' str in
  let l = List.filter (fun s -> not (String.startswith "#" s)) l in
  let str = String.concat "" l in
  String.fold_left (fun s c -> if c >= ' ' && c <= '~' then s ^ (String.of_char c) else s) "" str

(* obtain the BIOS string with the given name from dmidecode *)
let get_bios_string name =
  try
    let str, _ = Forkhelpers.execute_command_get_output dmidecode_prog [dmidecode_prog; "-s"; name] in
    let str = String.trim (remove_invisible str) in
    if str = "" || str = "Not Specified" then ""
    else str
  with _ -> ""

(* Obtain the Type 11 OEM strings from dmidecode, and prepend with the standard ones. *)
let get_oem_strings () =
  let standard = Xapi_globs.standard_type11_strings in
  try
    let result, _ = Forkhelpers.execute_command_get_output dmidecode_prog [dmidecode_prog; "-t11"; "-q"] in
    let n = List.length standard in
    let rec loop index a =
      try
        let b = String.index_from result a ':' in
        let c = String.index_from result b '\n' in
        let str = "oem-" ^ (string_of_int index) in
        let value = String.trim (remove_invisible (String.sub result (b+2) (c-b-2))) in
        if value <> "" then
          (str, value) :: loop (index+1) c
        else
          loop index c
      with _ -> []
    in
    standard @ (loop (n+1) 0)
  with _ -> standard

(* Get the HP-specific ROMBIOS OEM string:
 * 6 bytes from the memory starting at 0xfffea *)
let get_hp_rombios () =
  let hp_rombios = Bytes.make 6 ' ' in
  begin try
      let mem = Unix.openfile "/dev/mem" [Unix.O_RDONLY] 0 in
      Stdext.Pervasiveext.finally (fun () ->
          ignore (Unix.lseek mem 0xfffea Unix.SEEK_SET);
          ignore (Unix.read mem hp_rombios 0 6))
        (fun () -> Unix.close mem)
    with _ -> ()
  end;
  let hp_rombios = Bytes.unsafe_to_string hp_rombios in
  if String.trim (remove_invisible hp_rombios) = "COMPAQ" then "COMPAQ" else ""

(* Get host bios strings *)
let get_host_bios_strings ~__context =
  info "Getting host BIOS strings.";
  (* named BIOS strings *)
  let dmidecode_strings = ["bios-vendor"; "bios-version"; "system-manufacturer";
                           "system-product-name"; "system-version"; "system-serial-number"] in
  let named_strings = List.map (fun str -> str, (get_bios_string str)) dmidecode_strings in
  (* type 11 OEM strings *)
  let oem_strings = get_oem_strings () in
  (* HP-specific ROMBIOS OEM string *)
  let hp_rombios = ["hp-rombios", get_hp_rombios ()] in
  named_strings @ oem_strings @ hp_rombios
