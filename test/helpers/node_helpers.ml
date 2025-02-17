open! Core_kernel
open! Js_of_ocaml
open Virtual_dom

type element =
  { tag_name : string
  ; attributes : (string * string) list [@sexp.list]
  ; string_properties : (string * string) list [@sexp.list]
  ; bool_properties : (string * bool) list [@sexp.list]
  ; styles : (string * string) list [@sexp.list]
  ; handlers : (string * Handler.t) list [@sexp.list]
  ; hooks : (string * Vdom.Attr.Hooks.For_testing.Extra.t) list [@sexp.list]
  ; key : string option [@sexp.option]
  ; children : t list [@sexp.list]
  }
[@@deriving sexp_of]

and t =
  | Text of string
  | Element of element
  | Widget of Sexp.t
[@@deriving sexp_of]

let is_tag ~tag = function
  | Element { tag_name; _ } -> String.equal tag_name tag
  | _ -> false
;;

let has_class ~cls = function
  | Element { attributes; _ } ->
    List.exists attributes ~f:(function
      | "class", data ->
        data |> String.split ~on:' ' |> List.exists ~f:(String.equal cls)
      | _ -> false)
  | _ -> false
;;

let rec map t ~f =
  match f t with
  | `Replace_with t -> t
  | `Continue ->
    (match t with
     | Text _ | Widget _ -> t
     | Element element ->
       let children = List.map element.children ~f:(fun ch -> map ch ~f) in
       Element { element with children })
;;



type hidden_soup = Hidden_soup : _ Soup.node -> hidden_soup

type 'a breadcrumb_preference =
  | Don't_add_breadcrumbs : unit breadcrumb_preference
  | Add_breadcrumbs : (Soup.element Soup.node -> t) breadcrumb_preference

module Soup_id = Unique_id.Int ()

let soup_id_key = "soup-id"

let to_lambda_soup (type a) t (breadcrumb_preference : a breadcrumb_preference)
  : hidden_soup * a
  =
  let t_by_soup_id = String.Table.create () in
  let rec convert t =
    match t with
    | Text s -> Hidden_soup (Soup.create_text s)
    | Widget w ->
      let info_text = Soup.create_text (Sexp.to_string w) in
      let element = Soup.create_element "widget" ~attributes:[] in
      Soup.append_child element info_text;
      Hidden_soup element
    | Element
        { tag_name
        ; attributes
        ; string_properties
        ; bool_properties
        ; handlers
        ; key
        ; children
        ; hooks
        ; styles = _
        } ->
      let key_attrs =
        match key with
        | Some key -> [ "key", key ]
        | None -> []
      in
      let soup_id_attrs =
        match breadcrumb_preference with
        | Don't_add_breadcrumbs -> []
        | Add_breadcrumbs ->
          let soup_id = Soup_id.create () |> Soup_id.to_string in
          Hashtbl.add_exn t_by_soup_id ~key:soup_id ~data:t;
          [ soup_id_key, soup_id ]
      in
      let handler_attrs =
        List.map handlers ~f:(fun (name, _) -> name, "<event-handler>")
      in
      let hook_attrs = List.map hooks ~f:(fun (name, _) -> name, "<hook>") in
      let bool_properties =
        List.map bool_properties ~f:(fun (name, bool) -> name, Bool.to_string bool)
      in
      let attributes =
        [ hook_attrs
        ; key_attrs
        ; soup_id_attrs
        ; handler_attrs
        ; attributes
        ; string_properties
        ; bool_properties
        ]
        |> List.concat
        |> String.Map.of_alist_exn (* Raise on duplicate attributes *)
        |> Map.to_alist
      in
      let element = Soup.create_element tag_name ~attributes in
      List.iter children ~f:(fun child ->
        let (Hidden_soup child) = convert child in
        Soup.append_child element child);
      Hidden_soup element
  in
  ( convert t
  , match breadcrumb_preference with
  | Don't_add_breadcrumbs -> ()
  | Add_breadcrumbs ->
    fun soup ->
      (match Soup.attribute soup_id_key soup with
       | None -> raise_s [%message "Soup.node has no soup-id attribute"]
       | Some soup_id -> Hashtbl.find_exn t_by_soup_id soup_id) )
;;

let _to_string_html t =
  let Hidden_soup soup, () = to_lambda_soup t Don't_add_breadcrumbs in
  Soup.to_string soup
;;

(* Printing elements in single-line and multiline formats is essentially the
   same. The main difference is what attributes are separated by: in
   single-line, they are separated just by spaces, but in multiline they are
   separated by a newline and some indentation.
*)
let bprint_element
      buffer
      ~sep
      ~before_styles
      ~should_print_styles
      { tag_name
      ; attributes
      ; string_properties
      ; bool_properties
      ; styles
      ; handlers
      ; key
      ; hooks
      ; children = _
      }
  =
  bprintf buffer "<%s" tag_name;
  let has_printed_an_attribute = ref false in
  let bprint_aligned_indent () =
    if !has_printed_an_attribute
    then bprintf buffer "%s" sep
    else (
      has_printed_an_attribute := true;
      bprintf buffer " ")
  in
  Option.iter key ~f:(fun key ->
    bprint_aligned_indent ();
    bprintf buffer "@key=%s" key);
  List.iter attributes ~f:(fun (k, v) ->
    bprint_aligned_indent ();
    bprintf buffer "%s=\"%s\"" k v);
  List.iter string_properties ~f:(fun (k, v) ->
    bprint_aligned_indent ();
    bprintf buffer "#%s=\"%s\"" k v);
  List.iter bool_properties ~f:(fun (k, v) ->
    bprint_aligned_indent ();
    bprintf buffer "#%s=\"%b\"" k v);
  List.iter hooks ~f:(fun (k, v) ->
    bprint_aligned_indent ();
    bprintf
      buffer
      "%s=%s"
      k
      (v |> [%sexp_of: Vdom.Attr.Hooks.For_testing.Extra.t] |> Sexp.to_string_mach));
  List.iter handlers ~f:(fun (k, _) ->
    bprint_aligned_indent ();
    bprintf buffer "%s={handler}" k);
  if not (List.is_empty styles)
  then (
    bprint_aligned_indent ();
    bprintf buffer "style={";
    if should_print_styles
    then (
      List.iter styles ~f:(fun (k, v) ->
        bprint_aligned_indent ();
        bprintf buffer "%s%s: %s;" before_styles k v);
      bprint_aligned_indent ())
    else bprintf buffer "...";
    bprintf buffer "}");
  bprintf buffer ">"
;;

let bprint_element_single_line buffer element =
  bprint_element buffer ~sep:" " ~before_styles:"" element
;;

let bprint_element_multi_line buffer ~indent element =
  let align_with_first_attribute = String.map element.tag_name ~f:(Fn.const ' ') ^ "  " in
  let sep = "\n" ^ indent ^ align_with_first_attribute in
  bprint_element buffer ~sep ~before_styles:"  " element
;;

let to_string_html ?(should_print_styles = true) t =
  (* Keep around the buffer so that it is not re-allocated for every element *)
  let single_line_buffer = Buffer.create 200 in
  let rec recurse buffer ~depth =
    let indent = String.init (depth * 2) ~f:(Fn.const ' ') in
    function
    | Text s -> bprintf buffer "%s%s" indent s
    | Element element ->
      bprintf buffer "%s" indent;
      Buffer.reset single_line_buffer;
      bprint_element_single_line ~should_print_styles single_line_buffer element;
      if Buffer.length single_line_buffer < 100 - String.length indent
      then Buffer.add_buffer buffer single_line_buffer
      else bprint_element_multi_line ~should_print_styles buffer ~indent element;
      let children_should_collapse =
        List.for_all element.children ~f:(function
          | Text _ -> true
          | _ -> false)
        && List.fold element.children ~init:0 ~f:(fun acc child ->
          match child with
          | Text s -> acc + String.length s
          | _ -> acc)
           < 80 - String.length indent
      in
      let depth = if children_should_collapse then 0 else depth + 1 in
      List.iter element.children ~f:(fun child ->
        if children_should_collapse then bprintf buffer " " else bprintf buffer "\n";
        recurse buffer ~depth child);
      if children_should_collapse
      then bprintf buffer " "
      else (
        bprintf buffer "\n";
        bprintf buffer "%s" indent);
      bprintf buffer "</%s>" element.tag_name
    | Widget s -> bprintf buffer "%s<widget %s />" indent (Sexp.to_string s)
  in
  let buffer = Buffer.create 100 in
  recurse buffer ~depth:0 t;
  Buffer.contents buffer
;;

let select t ~selector =
  let Hidden_soup element, find_t_by_soup_exn = to_lambda_soup t Add_breadcrumbs in
  let soup = Soup.create_soup () in
  Soup.append_root soup element;
  soup |> Soup.select selector |> Soup.to_list |> List.map ~f:find_t_by_soup_exn
;;

let select_first t ~selector = select t ~selector |> List.hd

let select_first_exn t ~selector =
  match select_first t ~selector with
  | Some node -> node
  | None ->
    raise_s
      [%message
        "Failed to find element matching selector"
          (selector : string)
          ~from_node:(to_string_html t : string)]
;;

let unsafe_of_js_exn =
  let make_text_node (text : Js.js_string Js.t) = Text (Js.to_string text) in
  let make_element_node
        (tag_name : Js.js_string Js.t)
        (children : t Js.js_array Js.t)
        (handlers : (Js.js_string Js.t * Js.Unsafe.any) Js.js_array Js.t)
        (attributes : (Js.js_string Js.t * Js.js_string Js.t) Js.js_array Js.t)
        (string_properties : (Js.js_string Js.t * Js.js_string Js.t) Js.js_array Js.t)
        (bool_properties : (Js.js_string Js.t * bool Js.t) Js.js_array Js.t)
        (styles : (Js.js_string Js.t * Js.js_string Js.t) Js.js_array Js.t)
        (hooks : (Js.js_string Js.t * Vdom.Attr.Hooks.For_testing.Extra.t) Js.js_array Js.t)
        (key : Js.js_string Js.t Js.Opt.t)
    =
    let tag_name = tag_name |> Js.to_string in
    let children = children |> Js.to_array |> Array.to_list in
    let handlers =
      handlers
      |> Js.to_array
      |> Array.to_list
      |> List.map ~f:(fun (s, h) ->
        let name = Js.to_string s in
        name, Handler.of_any_exn h ~name)
    in
    let attributes =
      attributes
      |> Js.to_array
      |> Array.to_list
      |> List.map ~f:(fun (k, v) -> Js.to_string k, Js.to_string v)
    in
    let hooks =
      hooks
      |> Js.to_array
      |> Array.to_list
      |> List.map ~f:(fun (k, v) -> Js.to_string k, v)
    in
    let string_properties =
      string_properties
      |> Js.to_array
      |> Array.to_list
      |> List.map ~f:(fun (k, v) -> Js.to_string k, Js.to_string v)
    in
    let bool_properties =
      bool_properties
      |> Js.to_array
      |> Array.to_list
      |> List.map ~f:(fun (k, v) -> Js.to_string k, Js.to_bool v)
    in
    let styles =
      styles
      |> Js.to_array
      |> Array.to_list
      |> List.map ~f:(fun (k, v) -> Js.to_string k, Js.to_string v)
    in
    let key = key |> Js.Opt.to_option |> Option.map ~f:Js.to_string in
    Element
      { tag_name
      ; children
      ; handlers
      ; attributes
      ; string_properties
      ; bool_properties
      ; key
      ; hooks
      ; styles
      }
  in
  let make_widget_node (id : _ Type_equal.Id.t) (info : Sexp.t Lazy.t option) =
    match info with
    | Some sexp -> Widget (Lazy.force sexp)
    | None -> Widget (Sexp.Atom (Type_equal.Id.name id))
  in
  let raise_unknown_node_type node_type =
    let node_type = Js.to_string node_type in
    raise_s [%message "unrecognized node type" (node_type : string)]
  in
  let f =
    Js.Unsafe.pure_js_expr
      {js|
   // Convert analyzes a Vdom node that was produced by [Node.to_js] and walks the tree
   // recursively, calling make_text_node, make_element_node, and make_widget_node depending
   // on the type of node.
   (function convert(node, make_text_node, make_element_node, make_widget_node, raise_unknown_node_type) {
       switch (node.type) {
           case 'VirtualText':
               return make_text_node(node.text);
           case 'Widget':
               return make_widget_node(node.id, node.info);
           case 'VirtualNode':
               var attributes = node.properties.attributes || {};
               var attr_list = Object.keys(attributes).map(function(key) {
                   return [0, key, attributes[key].toString()];
               });
               var children = node.children.map(function(node) {
                   return convert(node, make_text_node, make_element_node, raise_unknown_node_type);
               });
               var handlers =
                   Object.keys(node.properties)
                   .filter(function(key) {
                       // This is a bit of a hack, but it works for all the handlers that we
                       // have defined at the moment.  Consider removing the 'on' check?
                       return key.startsWith("on") && typeof node.properties[key] === 'function';
                   })
                   .map(function(key) {
                       // [0, ...] is how to generate an OCaml tuple from the JavaScript side.
                       return [0, key, node.properties[key]];
                   });
               var string_properties =
                   Object.keys(node.properties)
                   .filter(function(key) {
                       return typeof node.properties[key] === 'string';
                   })
                   .map(function(key) {
                       return [0, key, node.properties[key]]
                   });
               var bool_properties =
                   Object.keys(node.properties)
                   .filter(function(key) {
                     return typeof node.properties[key] === 'boolean';
                   })
                   .map(function(key) {
                       return [0, key, node.properties[key]]
                   });
               var styles =
                   Object.keys(node.properties.style ? node.properties.style : {})
                   .filter(function(key) {
                       return typeof node.properties.style[key] === 'string';
                   })
                   .map(function(key) {
                       return [0, key, node.properties.style[key]]
                   });
               var hooks =
                   Object.keys(node.properties)
                   .filter(function(key) {
                       return typeof node.properties[key] === 'object' &&
                           typeof node.properties[key]['extra'] === 'object';
                   })
                   .map(function(key) {
                       return [0, key, node.properties[key]['extra']]
                   });
               return make_element_node(
                   node.tagName,
                   children,
                   handlers,
                   attr_list,
                   string_properties,
                   bool_properties,
                   styles,
                   hooks,
                   node.key || null);
           default:
               raise_unknown_node_type("" + node.type);
       }
   })
   |js}
  in
  fun value ->
    Js.Unsafe.fun_call
      f
      [| value
       ; Js.Unsafe.inject (Js.wrap_callback make_text_node)
       ; Js.Unsafe.inject (Js.wrap_callback make_element_node)
       ; Js.Unsafe.inject (Js.wrap_callback make_widget_node)
       ; Js.Unsafe.inject (Js.wrap_callback raise_unknown_node_type)
      |]
;;

let unsafe_convert_exn vdom_node =
  vdom_node |> Virtual_dom.Vdom.Node.to_raw |> Js.Unsafe.inject |> unsafe_of_js_exn
;;

let get_handlers (node : t) =
  match node with
  | Element { handlers; _ } -> handlers
  | _ -> raise_s [%message "expected Element node" (node : t)]
;;

let trigger_many ?extra_fields node ~event_names =
  let all_handlers = get_handlers node in
  let count =
    List.count event_names ~f:(fun event_name ->
      match List.Assoc.find all_handlers event_name ~equal:String.equal with
      | None -> false
      | Some handler ->
        Handler.trigger handler ?extra_fields;
        true)
  in
  match count with
  | 0 -> raise_s [%message "No handler found on element" (event_names : string list)]
  | _ -> ()
;;

let trigger ?extra_fields node ~event_name =
  trigger_many ?extra_fields node ~event_names:[ event_name ]
;;

let get_hook_value : type a. t -> type_id:a Type_equal.Id.t -> name:string -> a =
  fun t ~type_id ~name ->
  match t with
  | Element { hooks; _ } ->
    (match List.Assoc.find ~equal:String.equal hooks name with
     | Some hook ->
       let (Vdom.Attr.Hooks.For_testing.Extra.T { type_id = type_id_v; value }) = hook in
       (match Type_equal.Id.same_witness type_id_v type_id with
        | Some T -> value
        | None ->
          failwithf
            "get_hook_value: a hook for %s was found, but the type-ids were not the same; \
             are you using the same type-id that you got from the For_testing module from \
             your hook creator?"
            name
            ())
     | None -> failwithf "get_hook_value: no hook found with name %s" name ())
  | Text _ -> failwith "get_hook_value: expected Element, found Text"
  | Widget _ -> failwith "get_hook_value: expected Element, found Widget"
;;

let trigger_hook t ~type_id ~name ~arg =
  Ui_event.Expert.handle ((get_hook_value t ~type_id ~name) arg)
;;

module User_actions = struct
  let click_on node = trigger ~event_name:"onclick" node

  let input_text element ~text =
    let tag_name =
      match element with
      | Element { tag_name; _ } -> tag_name
      | other ->
        let node = to_string_html other in
        raise_s [%message (node : string) "is not an element"]
    in
    let value_element =
      (* When an [on_input] event is fired, in order to pull the value of
         the element, [Virtual_dom.Vdom.Attr.on_input_event] looks at the
         "target" property on the event and tries to coerce that value to one
         of [input element, select element, textarea element].  This coercion
         function is implemented in [Js_of_ocaml.Dom_html.CoerceTo], and the
         way that the coercion function works is by comparing the value of
         the [tagName] property on the event target to the string of the tag
         name that the coercion is targeting.

         By mocking out the [tagName] and [value] properties on the target of
         the event, we can trick the virtual_dom code into handling our event
         as though there was a real DOM element! *)
      Js.Unsafe.inject
        (object%js
          val tagName = Js.string tag_name

          val value = Js.string text
        end)
    in
    let extra_fields = [ "target", value_element ] in
    let event_names = [ "oninput"; "onchange" ] in
    trigger_many element ~extra_fields ~event_names
  ;;

  let prevent_default = [ "preventDefault", Js.Unsafe.inject Fn.id ]

  let enter element =
    trigger element ~event_name:"ondragenter" ~extra_fields:prevent_default
  ;;

  let over element =
    trigger element ~event_name:"ondragover" ~extra_fields:prevent_default
  ;;

  let drag element = trigger element ~event_name:"ondragstart"
  let leave element = trigger element ~event_name:"ondragleave"
  let drop element = trigger element ~event_name:"ondrop"
  let end_ element = trigger element ~event_name:"ondragend"
end
