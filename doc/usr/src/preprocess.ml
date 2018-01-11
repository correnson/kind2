(* This markdown preprocessor aims at performing basic safety checks regarding
   the links in markdown document spread over several files, and prepare a
   single file to give to pandoc.

   In the following we say

   * **internal link** for a link to file `B` in file `A` with `A!=B`
   * **local link** for a link in file `A` to a section of file `A`

   # Assumptions

   Links between files
   
   * all start with `./`,
   * and point to a section, not to a file.

   Typically `[bla](./path/to/file#section-label)` is ok. But none of the
   following is:

   * `[bla](path/to/file#section-label)`
   * `[bla](./path/to/file)`
   * `[bla](file#section-label)`

   /!\ File-to-file links not following the conventions will not be checked,
   and will not be formatted for pandoc. This means they will result in dead
   links that pandoc will remove. /!\

   Local links are as usual: `[bla](#section-in-same-file)`.

   # Safety checks

   * links between files are well defined:
     the file and section pointed at exist,
   * links between files are unambiguous:
     there is only one section in the file pointed at with this label.

   Also, warning are issued if some sections in a file have the same name,
   since in markdown this means they have the same label. This is not an error
   unless the ambiguous label of this file is pointed at.

   # Encoding for pandoc

   The trick is to rewrite the internal and local links so that they are
   well-defined and unambiguous when inlining everything.
   We use the `Unix` module to get the **inode id** of the different files, and
   will use that as an identifier.

   So say file `bla.md` has an inode `42`. Then a local link like
   `[bla](#some-section)` will be rewritten as `[bla](#42-some-section)`. If a
   different files points to `bla.md`, **e.g.** `[bla](./bla.md#some-section)`,
   it will be rewritten the same way: `[bla](#42-some-section)` here.

   Naturally, the labels of the section in `bla.md` are also redefined to be
   consistent with this. So section headers `## Some section` in `bla.md`
   become `## Some section {#42-some-section}`. *)


(* Exception raised if a label is defined two times in the same file, and is
   pointed at somewhere. Contains
   * the name of the file the dead link points to,
   * the redundant label. *)
exception LabelClash of string * string
(* Exception raised if a local link points to an inexistent label. Contains
   * the name of the file the dead link points to,
   * the dead label. *)
exception DeadLabelLink of string * string
(* Exception raised if a local link points to an inexistent file. Contains
   * the name of the dead file the link points to,
   * the label. *)
exception DeadFileLink of string * string
(* Exception raised if a file is linked directly (without a label). Contains
   * the name of the file it point to. *)
exception DirectLink of string

(* Shorthand for [Format.printf]. *)
let printf = Format.printf

(* Helper function for geniric list pretty printing. *)
let rec pp_print_list pp sep fmt = function
  | [] -> ()
  | [ h ] -> pp fmt h
  | h :: tail ->
    Format.fprintf fmt "%a" pp h ;
    Format.fprintf fmt sep ;
    pp_print_list pp sep fmt tail

(* Prints usage. *)
let print_usage () =
  printf "\
    @,\
    Usage: ./preprocess <out> [<in>]+@.  @[<v>\
      Checks the local links in a multi file markdown document, and@,\
      generates a md file that can be passed to pandoc directly.@,\
      The final document will have a structure consistent with the order@,\
      of the input files.@,\
      The arguments are:@,\
      * <out> is the name of the file the preprocessor writes to, and@,\
      * <in> is an markdown file from the document.@,\
    @]@.\
  "

(* Prints some lines formatted as an error and exits with code [-1]. *)
let error lines =
  printf
    "\027[31mError:\027[0m@.  @[<v>%a@]@."
    (pp_print_list Format.pp_print_string "@,")
    lines ;
  -1 |> exit

(* Prints some lines formatted as a warning. *)
let warning lines =
  printf
    "\027[31mWarning:\027[0m@.  @[<v>%a@]@.@."
    (pp_print_list Format.pp_print_string "@,")
    lines

(* Prints usage, then some lines formatted as an error and exits with code
   [-1]. *)
let usage_error lines =
  print_usage () ;
  printf "@." ;
  error lines

(* Prints a list of link exceptions as errors, and exits with code [-1]. *)
let link_error errors =
  printf "\027[31mError:\027[0m@.  @[<v>" ;
  errors |> List.iter (
    fun (file, errs) ->
    printf "on file %s@,  @[<v>" file ;
    errs |> List.iter (
      function
      | LabelClash (file, label) ->
        printf "link to overloaded label \"%s\" in file \"%s\"@," label file
      | DeadLabelLink (file, label) ->
        printf "link to inexistent label \"%s\" in file \"%s\"@," label file
      | DeadFileLink (file, label) ->
        printf "link to inexistent file \"%s\" (label is \"%s\")@," file label
      | DirectLink file ->
        printf "direct link to file %s@," file
      | _ -> failwith "unexpected exception"
    ) ;
    printf "@]@,"
  ) ;
  printf "@]@." ;
  -1 |> exit

(* Prints an error for not finding the sed command and exits with [-1]. *)
let sed_error () =
  error [
    "cannot find GNU \"sed\" command:" ;
    "if you use OSX, please install \"gsed\""
  ]

(* Tests [sed] to see if it has the GNU extension. If that fails, checks for
   [gsed]. If that fails, calls [sed_error]. *)
let sed_cmd =
  try
    let test =
      "echo \"test\" | sed -e \"s:.*:echo \\\"test\\\":e\" &> /dev/null"
    in
    let channels = Unix.open_process test in
    ( match Unix.close_process channels with
      | Unix.WEXITED 0 -> "sed"
      | _ -> Unix.Unix_error (Unix.EINVAL, "sed", "") |> raise )
  with Unix.Unix_error _ ->
    (* [sed] is not GNU sed, trying [gsed]. *)
    ( try
        let test =
          "echo \"test\" | gsed -e \"s:.*:echo \\\"test\\\":e\" &> /dev/null"
        in
        let channels = Unix.open_process test in
        ( match Unix.close_process channels with
          | Unix.WEXITED 0 -> "gsed"
          | _ -> Unix.Unix_error (Unix.EINVAL, "gsed", "") |> raise )
      with Unix.Unix_error _ ->
        sed_error () )



(* Aggregates the helper functions for IOs and running bash commands. *)
module IO = struct

  (* Splits a string w.r.t. a character. *)
  let split sep str =

    let rec loop l str =
      try
        (* Retrieving next index of the seperator char. *)
        let i = String.index str sep in
        (* Extracting head. *)
        let head = String.sub str 0 i in
        let len = String.length str in
        (* If there's nothing after the separator we're done. *)
        if i + 1 >= len - 1 then head :: l |> List.rev
        (* Otherwise we get the tail and loop. *)
        else (
          String.sub str (i + 1) (len - i - 1) |> loop ( head :: l )
        )

      (* If [sep] is not in [str] we're done. *)
      with Not_found -> str :: l |> List.rev
    in

    loop [] str

  (* Replaces all occurences of [c1] by [c2] in a string. *)
  let subst c1 c2 =
    String.map (
      function
      | c when c = c1 -> c2
      | c -> c
    )

  (* Runs a command and returns its stdout as a single string. *)
  let run cmd =
    let ic, oc = Unix.open_process cmd in
    let buf = Buffer.create 16 in
    ( try
        while true do
          Buffer.add_channel buf ic 1
        done
      with End_of_file -> () );
    let _ = Unix.close_process (ic, oc) in
    Buffer.contents buf

  (* Returns the inode index of a file. *)
  let node_of_file file =
    match
      "ls -i " ^ file ^ " | sed -e 's:^\\([0-9]*\\).*$:\\1:'"
      |> run |> String.trim |> split '\n'
    with
    | node :: [] -> node
    | _ -> failwith "unexpected result for \"ls -i\""

  (* Returns the file path from an inode index. *)
  let file_of_node node =
    match
      Format.sprintf "find . -inum %s -print" node
      |> run |> String.trim |> split '\n'
    with
    | file :: [] -> file
    | _ -> failwith "unexpected result for \"find . -inum\""

  (* Rewrites a path w.r.t. another path. *)
  let transitive_path from path =
    (Filename.dirname from) ^ "/" ^ path

  (* Returns the list of labels for the sections of a file. *)
  let labels_of file =
    (* Filters [#]s, removes double spaces. *)
    let cmd =
      Format.sprintf "\
        grep -e \"^#\" %s | \
        sed -e 's:\\# ::' -e 's:\\#::g' -e 's:  : :' \
      " file
    in
    run cmd
    |> String.trim
    |> split '\n'
    |> List.map (subst ' ' '-')


  (* Returns the list of local links (file / label pairs) from a file. *)
  let internal_links_of file =
    let cmd =
      Format.sprintf "\
        grep -e \"](\\./.*\\.md[^)]*)\" %s | \
        sed -e 's:.*](\\(\\./[^)]*\\)).*:\\1:'\
      " file
    in
    (* printf "internal_links_of %s@." file ;
    printf "> %s@." cmd ; *)
    run cmd
    |> String.trim
    |> split '\n'
    |> List.filter (fun s -> s <> "")
    |> (fun lines ->
        (* printf
          " output: [@[<v>%a@]]@.@."
          (pp_print_list Format.pp_print_string "@,")
          lines ; *)
        List.map (split '#') lines)

  (* Escapes [`] and double quotes characters. *)
  let sanitize str =
    let rec loop index str =
      if index >= String.length str then str else (
        (* printf "str: %s@." str ;
        printf "index: %d@." index ;
        printf "char: %c@." (String.get str index) ; *)
        match String.get str index with
        | '`' | '\'' ->
          let prefix = String.sub str 0 index in
          let suffix =
            (String.length str) - (String.length prefix)
            |> String.sub str index
          in
          prefix ^ "\\" ^ suffix
          |> loop (index + 2)
        | '"' ->
          let prefix = String.sub str 0 index in
          let suffix =
            (String.length str) - (String.length prefix)
            |> String.sub str index
          in
          prefix ^ "\\\\\\" ^ suffix
          |> loop (index + 4)
        | _ -> loop (index+1) str
      )
    in
    loop 0 str

  (* Echoes a line after sanitizing it, pipes it to some commands, and
     removes newlines. *)
  let echo_pipe cmds line =
    let sanitized = sanitize line in
    let cmd =
      Format.asprintf "\
        echo \"%s\" | %a | tr -d '\\n'\
      " sanitized (pp_print_list Format.pp_print_string " | ") cmds
    in
    run cmd
    |> fun line' ->
      if line <> line' then
        printf "> @[<v>[%s]@,[%s]@,@]@." line line' ;
      line'

  (* Command rewriting the internal links between files. *)
  let rewrite_links dirname =
    Format.sprintf "\
      sed -e 's:\
        ](\\./\\([^)]*\\)#\\([^)]*\\)):$(\
          ls -i %s/\\1 | \
          sed -e \"s/ .*$//\" | \
          xargs printf \"](#n%%s-\\2)\"\
        )\
      :g' | \
      sed -e 's:^\\(.*\\)$:echo \"\\1\":' | \
      sed -e 's:`:\\\\`:g' | \
      sh | \
      tr -d '\n'\
    " dirname

  (* Command rewriting the links local to a file. *)
  let rewrite_local_links prefix =
    Format.sprintf "\
      sed -e 's:\
        ](#\\([^)]*\\)):\
        ](#%s-\\1)\
      :g'\
    " prefix

  (* Rewrites links to pictures on the repo. *)
  let rewrite_pics dirname =
    Format.sprintf "\
      %s -e 's:\
        ](\\./\\([^)]*\\)\\.\\(jpg\\|png\\)):\
        ](%s/\\1\\.\\2)\
      :g'\
    " sed_cmd dirname

  (* Rewrites the labels of sections. *)
  let rewrite_label prefix line =
    if String.length line < 1 then line
    else if String.get line 0 = '#' then (

      let rec get_head head index s =
        match String.get s index with
        | '#' -> get_head (head ^ "#") (index + 1) s
        | ' ' | '\t' -> get_head head (index + 1) s
        | _ -> (
          head,
          (String.length s) - index |> String.sub s index
        )
      in

      let head, tail = get_head "" 0 line in

      let rec get_label is_ws_rep label index =
        if index >= String.length tail then String.lowercase_ascii label else
          match String.get tail index with
          | ' ' | '\t' ->
            get_label
              true
              ( if is_ws_rep then label else label ^ "-" )
              (index + 1)
          | '/' ->
            get_label
              true
              ( if is_ws_rep then label else label ^ "-" )
              (index + 1)
          | '-'
          | ','
          | '.'
          | '`' -> index + 1 |> get_label is_ws_rep label
          | c ->
            get_label
              false
              ( Format.sprintf "%s%c" label c )
              (index + 1)
      in

      let label = get_label false "" 0 in

      Format.sprintf "%s %s {#%s-%s}" head tail prefix label
      (* |> fun lbl -> printf "label: %s@." lbl ; lbl *)

    ) else line

  (* Rewrites the labels and the links of some files to a target for
     pandoc. *)
  let rewrite_to target files =
    (* Cleaning target file. *)
    Format.sprintf "rm -f %s ; touch %s" target target |> run |> ignore ;

    let tgt_chan = open_out target in

    let rec loop = function
      | file :: tail ->
        let src_chan = open_in file in
        let prefix = "n" ^ node_of_file file in
        let dirname = Filename.dirname file in
        ( try
            while true do
              input_line src_chan
              |> echo_pipe [
                (* rewrite_local_links prefix ; *)
                rewrite_links dirname ;
                (* rewrite_pics dirname ; *)
              ]
              (* |> fun smthng -> printf "line is: %s@." smthng ; smthng
              |> fun smthng -> printf "rewrite local links@." ; smthng
              |> rewrite_local_links prefix
              |> fun smthng -> printf "rewrite links@." ; smthng
              |> rewrite_links dirname
              |> fun smthng -> printf "rewrite pics@." ; smthng
              |> rewrite_pics dirname
              |> fun smthng -> printf "rewrite labels@." ; smthng *)
              |> rewrite_label prefix
              (* |> echo_pipe [ rewrite_pics dirname ] *)
              |> output_string tgt_chan ;
              output_string tgt_chan "\n"
            done ;
          with
          | End_of_file -> close_in src_chan
          | e -> close_in src_chan ; raise e ) ;
        output_string tgt_chan "\n\n\\newpage\n\n" ;
        flush tgt_chan ;
        loop tail
      | [] -> ()
    in

    (* Making sure we close the out channel for target. *)
    try loop files with e -> flush tgt_chan ; close_out tgt_chan ; raise e

end


(* Aggregates the structure and the functions for the context. A context
   stores
   * a map from files to the labels as defined in the files,
   * a map from files to overloaded labels. *)
module Context = struct

  (* Stores the map described at module level. *)
  type t = {
    (* The map from files to labels. *)
    mutable file2labels : (string * string list) list ;
    (* Map from files to redundant labels. *)
    mutable file2clashes : (string * string list) list ;
  }

  let clashes { file2clashes } = file2clashes

  (* Creates an empty context. *)
  let mk () = { file2labels = [] ; file2clashes = [] }

  (* Pretty prints a context. *)
  let pp_print fmt { file2labels } =
    Format.fprintf
      fmt
      "@[<v>%a@]"
      (pp_print_list
        (fun fmt (file,labels) ->
          Format.fprintf
            fmt "%s -> @[<hv>%a@]"
            file
            (pp_print_list Format.pp_print_string ",@ ")
            labels)
        "@,")
      file2labels

  (* Helper function for finding a label in a list of labels and doing
     something. *)
  let find_label_do f lbl l =
    let rec loop prefix = function
      | lbl' :: tail ->
        if lbl = lbl' then f prefix tail
        else loop (lbl' :: prefix) tail
      | [] -> raise Not_found
    in
    loop [] l

  (* Helper function for finding a file in a map and doing something. *)
  let find_node_do f node l =
    let rec loop prefix = function
      | ( (node',labels) as pair ) :: tail ->
        if node = node' then f prefix tail labels
        else loop (pair :: prefix) tail
      | [] -> raise Not_found
    in
    loop [] l

  (* Adds a label to a file in a map. Adds a new association if the file
     is not already there.

     Raises [LabelClash file,label] if the label is already defined for the
     file. *)
  let map_add_label map file label =
    let node = IO.node_of_file file in
    let label = String.lowercase_ascii label in
    let check_add prefix tail labels =
      if List.mem label labels
      then raise (LabelClash (file, label))
      else (node, label :: labels) :: tail |> List.rev_append prefix
    in

    try find_node_do check_add node map
    with Not_found -> List.rev_append (List.rev map) [ (node, [label]) ]

  (* Adds a label to a file in the clash map of a context. Adds a new
     association if the file is not already there. *)
  let add_clash t file label =
    let label = String.lowercase_ascii label in
    try
      t.file2clashes <- map_add_label t.file2clashes file label
    with LabelClash _ -> ()


  (* Adds a label to a file in a context. Adds a new association if the file
     is not already there.

     Adds a mapping from the file to the label if the label already exists. *)
  let add_label t file label =
    try
      t.file2labels <- map_add_label t.file2labels file label
    with LabelClash _ -> add_clash t file label


  (* Creates and populates a context from a list of files.

     Raises [LabelClash] if a label is defined twice in the same file. *)
  let of_files =
    let rec loop context = function
      | [] -> context
      | file :: tail ->
        (* Retrieve labels from file. *)
        IO.labels_of file
        (* Add them to the context one by one. *)
        |> List.iter (fun label -> add_label context file label) ;
        (* Looping on the other files. *)
        loop context tail
    in
    loop (mk ())

  (* Returns true if [label] is overloaded in [file]. *)
  let is_link_clash { file2clashes } file label =
    let node = IO.node_of_file file in
    try
      List.assoc node file2clashes
      |> List.mem label
    with Not_found -> false

  (* Checks that a label is defined for a file. *)
  let check_local_link { file2labels } file label =
    let node = IO.node_of_file file in
    (* Retrieving labels for this file. *)
    List.assoc node file2labels
    (* Checking if label's in there. *)
    |> List.mem label

  (* Checks that all the local links of a file are well-defined. *)
  let check_local_links context file =
    IO.internal_links_of file
    |> List.fold_left
      ( fun errs link ->
          match link with
          | [] ->
            Format.sprintf "unexpected link in file %s, empty list" file
            |> failwith
          | file' :: [] ->
            DirectLink file' :: errs
          | file' :: label :: [] -> (
            let file' = IO.transitive_path file file' in
            try
              if check_local_link context file' label then (
                if is_link_clash context file' label then
                  LabelClash (file', label) :: errs
                else errs
              ) else DeadLabelLink (file', label) :: errs
            with Not_found ->
              DeadFileLink (file', label) :: errs
          )
          | _ ->
            Format.sprintf
              "unexpected link in file %s, list has more than two elements"
              file
            |> failwith )
      []
    |> List.rev

end


(* Running. *)
let _ =

  printf "@.@." ;

  (* Extracting target file in input files, failing if arguments are
     illegal. *)
  let target, files = match Array.to_list Sys.argv with
    | [] | _ :: [] -> usage_error [
      "no arguments, need at least two."
    ]
    | _ :: _ :: [] -> usage_error [
      "no input file given, need at least one."
    ]
    | _ :: target :: files -> target, files
  in

  printf
    "Target: %s@.\
     Input:  @[<v>%a@]@.@."
    target (pp_print_list Format.pp_print_string "@ ") files ;

  (* let node = IO.node_of_file target in
  printf "node of \"%s\" is %s@." target node ; *)

  (* let path = IO.transitive_path target "../whatever" in
  printf "path: %s@." path ; *)

  (* Building context. *)
  let context = Context.of_files files in

  (* Issueing warning in case of label clash. *)
  ( match Context.clashes context with
    | [] -> ()
    | clashes ->
      clashes
      |> List.map (fun (file, labels) -> match labels with
        | [] ->
          Format.sprintf
            "illegal empty list of label in clash map for file %s"
            file
          |> failwith
        | label :: [] ->
          Format.sprintf
            "in file \"%s\" for label %s" (IO.file_of_node file) label
        | labels ->
          Format.asprintf
            "in file \"%s\" for labels %a"
            (IO.file_of_node file)
            (pp_print_list Format.pp_print_string ", ") labels
      )
      |> fun lines ->
        "Some sections have the same name and therefore the same label" ::
        lines
        |> warning ) ;

  printf "context:@.  @[<v>%a@]@." Context.pp_print context ;

  printf "@.@." ;

  (* Issueing error in case of link to overloaded label. *)
  ( match
      files
      |> List.fold_left
        ( fun errs file -> match Context.check_local_links context file with
          | [] -> errs
          | l -> (file, l) :: errs )
        []
      |> List.rev
    with
    | [] -> ()
    | l -> link_error l ) ;

  (* Rewriting labels and links. *)
  IO.rewrite_to target files ;

  printf "@.@." ;

  ()