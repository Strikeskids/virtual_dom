open! Core_kernel
open! Import

let show node =
  let t = node |> Node_helpers.unsafe_convert_exn in
  t |> [%sexp_of: Node_helpers.t] |> print_s;
  print_endline "----------------------";
  t |> Node_helpers.to_string_html |> print_endline
;;

let%expect_test "basic text" =
  show (Node.text "hello");
  [%expect {|
    (Text hello)
    ----------------------
    hello |}]
;;

let%expect_test "empty div" =
  show (Node.div [] []);
  [%expect
    {|
    (Element ((tag_name div)))
    ----------------------
    <div> </div> |}]
;;

let%expect_test "empty div" =
  show (Node.div [] []);
  [%expect
    {|
    (Element ((tag_name div)))
    ----------------------
    <div> </div> |}]
;;

let%expect_test "inner_html" =
  show
    (Node.inner_html
       ~tag:"div"
       []
       ~this_html_is_sanitized_and_is_totally_safe_trust_me:"<b>hi</b>");
  [%expect
    {|
    (Widget (inner-html div <b>hi</b>))
    ----------------------
    <widget (inner-html div <b>hi</b>) /> |}]
;;

let%expect_test "div with some text" =
  show (Node.div [] [ Node.text "hello world" ]);
  [%expect
    {|
    (Element ((tag_name div) (children ((Text "hello world")))))
    ----------------------
    <div> hello world </div> |}]
;;

let%expect_test "empty div with key" =
  show (Node.div ~key:"keykey" [] []);
  [%expect
    {|
    (Element ((tag_name div) (key keykey)))
    ----------------------
    <div @key=keykey> </div> |}]
;;

let%expect_test "empty div with string property" =
  show (Node.div [ Attr.string_property "foo" "bar" ] []);
  [%expect
    {|
    (Element ((tag_name div) (string_properties ((foo bar)))))
    ----------------------
    <div #foo="bar"> </div> |}]
;;

let%expect_test "empty div with bool property" =
  show (Node.div [ Attr.bool_property "foo" true ] []);
  [%expect
    {|
    (Element ((tag_name div) (bool_properties ((foo true)))))
    ----------------------
    <div #foo="true"> </div> |}]
;;

let%expect_test "nested div with span" =
  show (Node.div [] [ Node.span [] [] ]);
  [%expect
    {|
    (Element ((tag_name div) (children ((Element ((tag_name span)))))))
    ----------------------
    <div>
      <span> </span>
    </div> |}]
;;

let%expect_test "empty div with string attribute" =
  show (Node.div [ Attr.create "key" "value" ] []);
  [%expect
    {|
    (Element ((tag_name div) (attributes ((key value)))))
    ----------------------
    <div key="value"> </div> |}]
;;

let%expect_test "empty div with float attribute" =
  show (Node.div [ Attr.create_float "some_attr" 1.2345 ] []);
  [%expect
    {|
    (Element ((tag_name div) (attributes ((some_attr 1.2345)))))
    ----------------------
    <div some_attr="1.2345"> </div> |}]
;;

let%expect_test "widget" =
  let widget =
    Node.widget
      ~id:(Type_equal.Id.create ~name:"name_goes_here" [%sexp_of: opaque])
      ~init:(fun _ -> failwith "unreachable")
      ()
  in
  show widget;
  [%expect
    {|
    (Widget name_goes_here)
    ----------------------
    <widget name_goes_here /> |}]
;;

let%expect_test "widget with info" =
  let widget =
    Node.widget
      ~info:(lazy (Sexp.Atom "info name"))
      ~id:(Type_equal.Id.create ~name:"name_goes_here" [%sexp_of: opaque])
      ~init:(fun _ -> failwith "unreachable")
      ()
  in
  show widget;
  [%expect
    {|
    (Widget "info name")
    ----------------------
    <widget "info name" /> |}]
;;

let%expect_test "empty div with callback" =
  show (Node.div [ Attr.on_click (Fn.const Event.Ignore) ] []);
  [%expect
    {|
    (Element ((tag_name div) (handlers ((onclick <handler>)))))
    ----------------------
    <div onclick={handler}> </div> |}]
;;

let%expect_test "empty div with class list" =
  show (Node.div [ Attr.classes [ "a"; "b"; "c" ] ] []);
  [%expect
    {|
    (Element ((tag_name div) (attributes ((class "a b c")))))
    ----------------------
    <div class="a b c"> </div> |}]
;;

let%expect_test "empty div with id" =
  show (Node.div [ Attr.id "my-id" ] []);
  [%expect
    {|
    (Element ((tag_name div) (attributes ((id my-id)))))
    ----------------------
    <div id="my-id"> </div> |}]
;;

let%expect_test "later attributes override earlier ones" =
  show (Node.div [ Attr.id "overwritten-id"; Attr.id "final-id" ] []);
  [%expect
    {|
    ("WARNING: not combining attributes" (name id))
    (Element ((tag_name div) (attributes ((id final-id)))))
    ----------------------
    <div id="final-id"> </div> |}]
;;

let%expect_test "later properties override earlier ones" =
  show
    (Node.div
       [ Attr.string_property "prop" "overwritten-prop"
       ; Attr.string_property "prop" "final-prop"
       ]
       []);
  [%expect
    {|
    ("WARNING: not combining properties" (name prop))
    (Element ((tag_name div) (string_properties ((prop final-prop)))))
    ----------------------
    <div #prop="final-prop"> </div> |}]
;;

let%expect_test "no merging without [many]" =
  show (Node.div [ Attr.class_ "a"; Attr.class_ "b"; Attr.class_ "c" ] []);
  [%expect
    {|
    ("WARNING: not combining classes" (first (a)) (second (b)))
    ("WARNING: not combining classes" (first (b)) (second (c)))
    (Element ((tag_name div) (attributes ((class c)))))
    ----------------------
    <div class="c"> </div> |}]
;;

let%expect_test "merging only within [many]" =
  show (Node.div [ Attr.class_ "a"; Attr.class_ "b"; Attr.many [ Attr.class_ "c" ] ] []);
  [%expect
    {|
    ("WARNING: not combining classes" (first (a)) (second (b)))
    ("WARNING: not combining classes" (first (b)) (second (c)))
    (Element ((tag_name div) (attributes ((class c)))))
    ----------------------
    <div class="c"> </div> |}]
;;

let%expect_test "empty div with [many] classes" =
  show (Node.div [ Attr.many [ Attr.class_ "a"; Attr.class_ "b"; Attr.class_ "c" ] ] []);
  [%expect
    {|
    (Element ((tag_name div) (attributes ((class "a b c")))))
    ----------------------
    <div class="a b c"> </div> |}]
;;

let%expect_test "empty div with [many] different attributes" =
  show
    (Node.div
       [ Attr.many
           [ Attr.class_ "a"
           ; Attr.on_click (fun _ -> Ui_event.Ignore)
           ; Attr.style Css_gen.bold
           ; Attr.class_ "b"
           ; Attr.style (Css_gen.z_index 42)
           ; Attr.id "my-id"
           ; Attr.class_ "c"
           ; Attr.Always_focus_hook.attr `Read_the_docs__this_hook_is_unpredictable
           ; Attr.style (Css_gen.display `Table)
           ; Attr.class_ "d"
           ; Attr.on_click (fun _ -> Ui_event.Ignore)
           ; Attr.Always_focus_hook.attr `Read_the_docs__this_hook_is_unpredictable
           ]
       ]
       []);
  [%expect
    {|
    (Element
     ((tag_name div) (attributes ((id my-id) (class "a b c d")))
      (styles ((font-weight bold) (z-index 42) (display table)))
      (handlers ((onclick <handler>))) (hooks ((always-focus-hook ())))))
    ----------------------
    <div id="my-id"
         class="a b c d"
         always-focus-hook=()
         onclick={handler}
         style={
           font-weight: bold;
           z-index: 42;
           display: table;
         }> </div> |}]
;;

let%expect_test "empty div with tree of nested [many]" =
  show
    (Node.div
       [ Attr.many
           [ Attr.many [ Attr.class_ "a"; Attr.style (Css_gen.text_align `Center) ]
           ; Attr.many [ Attr.many [ Attr.class_ "b"; Attr.class_ "c" ] ]
           ; Attr.many
               [ Attr.many
                   [ Attr.many
                       [ Attr.id "my-id"; Attr.style (Css_gen.box_sizing `Border_box) ]
                   ]
               ]
           ]
       ]
       []);
  [%expect
    {|
    (Element
     ((tag_name div) (attributes ((id my-id) (class "a b c")))
      (styles ((text-align center) (box-sizing border-box)))))
    ----------------------
    <div id="my-id" class="a b c" style={ text-align: center; box-sizing: border-box; }> </div> |}]
;;
