open! Core_kernel
open Bonsai_web

module Model = struct
  type 'm t =
    { inner : 'm
    ; cursor : Spacetime_tree.Cursor.t
    ; history : 'm Spacetime_tree.t
    }
  [@@deriving fields]

  let create m =
    let history, cursor = Spacetime_tree.create m in
    { inner = m; cursor; history }
  ;;
end

module Action = struct
  type 'a t =
    | Inner of 'a
    | Set_cursor of Spacetime_tree.Cursor.t
  [@@deriving sexp_of]
end

module Result = struct
  type t = Vdom.Node.t -> Vdom.Node.t
end

let draw_history ~active_cursor ~inject ~data:_ ~cursor ~children =
  let children = List.rev children in
  let on_click = Vdom.Attr.on_click (fun _ -> inject (Action.Set_cursor cursor)) in
  let button_attrs =
    if Spacetime_tree.Cursor.equal active_cursor cursor
    then [ on_click; Vdom.Attr.class_ "current" ]
    else [ on_click ]
  in
  let my_node = Vdom.Node.button button_attrs [ Vdom.Node.text "●" ] in
  let children = Vdom.Node.div [ Vdom.Attr.class_ "ch" ] children in
  Vdom.Node.div [ Vdom.Attr.class_ "cnt" ] [ my_node; children ]
;;

let view cursor history ~inject =
  let open Incr.Let_syntax in
  let%map cursor = cursor
  and history = history in
  let spacetime =
    Spacetime_tree.traverse history ~f:(draw_history ~inject ~active_cursor:cursor)
  in
  let spacetime = Vdom.Node.div [ Vdom.Attr.class_ "history_wrapper" ] [ spacetime ] in
  fun window ->
    Vdom.Node.div [ Vdom.Attr.class_ "history_wrapper_wrapper" ] [ window; spacetime ]
;;

let create (type i m r) (inner_component : (i, m, r) Bonsai.t)
  : (i, m Model.t, r * Result.t) Bonsai.t
  =
  let (T (inner_unpacked, action_type_id)) = Bonsai.Expert.reveal inner_component in
  let open Incr.Let_syntax in
  Bonsai.Expert.of_full
    ~action_type_id:
      (Type_equal.Id.create
         ~name:(Source_code_position.to_string [%here])
         (function
           | Action.Inner a -> Type_equal.Id.to_sexp action_type_id a
           | Set_cursor cursor ->
             [%sexp "Set_cursor", (cursor : Spacetime_tree.Cursor.t)]))
    ~f:(fun ~input ~old_model ~(model : m Model.t Incr.t) ~inject ->
      let inject_inner a = inject (Action.Inner a) in
      let inner_model = model >>| Model.inner in
      let inner_old_model = old_model >>| Option.map ~f:Model.inner in
      let inner =
        Bonsai.Expert.eval
          ~input
          ~old_model:inner_old_model
          ~model:inner_model
          ~inject:inject_inner
          ~action_type_id
          inner_unpacked
      in
      let apply_action =
        let%map model = model
        and inner = inner in
        fun ~schedule_event -> function
          | Action.Inner a ->
            let inner : m =
              Bonsai.Expert.Snapshot.apply_action inner ~schedule_event a
            in
            let history, cursor =
              Spacetime_tree.append model.history model.cursor inner
            in
            { Model.inner; history; cursor }
          | Action.Set_cursor cursor ->
            let inner = Spacetime_tree.find model.history cursor in
            { model with inner; cursor }
      in
      let result =
        let%map inner = inner
        and view = view ~inject (model >>| Model.cursor) (model >>| Model.history) in
        Bonsai.Expert.Snapshot.result inner, view
      in
      let%map apply_action = apply_action
      and result = result in
      Bonsai.Expert.Snapshot.create ~result ~apply_action)
  |> Bonsai.Expert.conceal
;;
