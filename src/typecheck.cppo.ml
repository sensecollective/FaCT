open Pos
open Err
open Tast
open Pseudocode

#define err(p) InternalCompilerError("from source " ^ __LOC__ << p)
#define cerr(msg, p) InternalCompilerError("error: " ^ msg << p)

let wrap f pa = { pa with data=f pa.pos pa.data }
let xwrap f pa = f pa.pos pa.data

let rebind f pa = { pa with data=f pa }

#define mkpos make_ast p @@
(* p for 'uses Position' *)
#define pfunction wrap @@ fun p -> function
(* x for 'eXtract' *)
#define xfunction xwrap @@ fun p -> function

type tc_ctx_record = {
  rp       : label' ref;
  pc       : label';
  venv     : (var_name * variable_type) Env.env;
  fenv     : function_dec Env.env;
  add_stms : statement' list ref;
}

let make_fresh =
  let ctr = ref 0 in
  let make_fresh' name =
    ctr := !ctr + 1;
    "__v" ^ (string_of_int !ctr) ^ "_" ^ name
  in
    make_fresh'

let add_new_var venv x vt =
  let x' = { x with data=make_fresh x.data } in
  let entry = (x', vt) in
    Env.add_var venv x entry;
    Env.add_var venv x' entry;
    x'

let make_blit p n =
  ((if n then True else False), BaseET(mkpos Bool, mkpos Fixed Public))

let make_nlit p n =
  (IntLiteral n, BaseET(mkpos Num(abs n, n < 0), mkpos Fixed Public))


(* Predicates *)

let is_int = xfunction
  | UInt _ -> true
  | Int _ -> true
  | Num _ -> true
  | Bool -> false

let is_signed = xfunction
  | Int _ -> true
  | UInt _ -> false
  | Num(_,s) -> s
  | Bool -> false

let is_bool = xfunction
  | Bool -> true
  | _ -> false

let is_array = xfunction
  | BaseET _ -> false
  | ArrayET _ -> true

let param_is_ldynamic = xfunction
  | Param(_,{data=vty'}) ->
    begin
      match vty' with
        | ArrayVT({data=ArrayAT(_,{data=LDynamic _})},_,_) -> true
        | _ -> false
    end


(* Trivial conversions *)

let bconv = pfunction
  | Ast.UInt n -> UInt n
  | Ast.Int n -> Int n
  | Ast.Bool -> Bool

let mlconv = pfunction
  | Ast.Public -> Fixed Public
  | Ast.Secret -> Fixed Secret
  | Ast.Unknown -> raise (LabelError("Label inference not yet implemented!" << p))

let mconv = pfunction
  | Ast.Const -> Const
  | Ast.Mut -> Mut

let etype_conv = pfunction
  | Ast.BaseET(b,l) ->
    BaseET(bconv b, mlconv l)

let refvt_conv = pfunction
  | Ast.RefVT(b,l,m) ->
    RefVT(bconv b, mlconv l, mconv m)
  | Ast.ArrayVT _ -> raise @@ cerr("expected non-array, got array instead", p)


(* Simple Manipulation *)

let atype_update_lexpr lexpr' = pfunction
  | ArrayAT(bt,_) -> ArrayAT(bt, mkpos lexpr')

let aetype_update_lexpr' lexpr' = xfunction
  | ArrayET(a,ml,m) ->
    ArrayET(atype_update_lexpr lexpr' a, ml, m)

let aetype_update_mut' mut = function
  | ArrayET(a,ml,_) -> ArrayET(a, ml, mut)

let refvt_update_mut' mut = xfunction
  | RefVT(b,ml,_) -> RefVT(b, ml, mut)


(* Extraction *)

let type_of = xfunction
  | (_,ty) -> mkpos ty

let atype_of = xfunction
  | (_,ty) -> mkpos ty

let atype_to_btype = xfunction
  | ArrayAT(b,_) -> b

let type_out = xfunction
  | BaseET(b,ml) -> (b,ml)
  | ArrayET(a,ml,_) -> (atype_to_btype a,ml)

let expr_to_btype = xfunction
  | (_,BaseET(b,_)) -> b

let expr_to_ml = xfunction
  | (_,BaseET(_,ml)) -> ml

let expr_to_types = xfunction
  | (_,BaseET(b,ml)) -> b,ml

let atype_out = xfunction
  | ArrayET(a,ml,_) -> a,ml

let aetype_to_lexpr' = xfunction
  | ArrayET(a,ml,m) ->
    let ArrayAT(bt,lexpr) = a.data in
      lexpr.data

let refvt_to_betype' = xfunction
  | ArrayVT(a,ml,m) ->
    let ArrayAT(bt,lexpr) = a.data in
      BaseET(bt,ml)
let refvt_to_betype = rebind refvt_to_betype'

let refvt_type_out = xfunction
  | RefVT(b,ml,m) -> b,ml,m
  | ArrayVT(a,ml,m) -> (atype_to_btype a),ml,m

let refvt_to_lexpr = xfunction
  | ArrayVT(a,ml,m) ->
    let ArrayAT(bt,lexpr) = a.data in
      lexpr

let refvt_to_lexpr_option = xfunction
  | RefVT _ -> None
  | ArrayVT(a,ml,m) ->
    let ArrayAT(bt,lexpr) = a.data in
      Some lexpr.data

let refvt_to_etype' = xfunction
  | RefVT(b,ml,_) -> BaseET(b, ml)
  | ArrayVT(a,ml,m) -> ArrayET(a, ml, m)
let refvt_to_etype = rebind refvt_to_etype'

let argtype_of venv = xfunction
  | ByValue e ->
    let b,ml = expr_to_types e in
      mkpos RefVT(b,ml,mkpos Const)
  | ByRef x ->
    let _,vt = Env.find_var venv x in
      vt
  | ByArray({data=(aexpr,aty)}, mut) ->
    let b,ml = atype_out (mkpos aty) in
    mkpos ArrayVT(b,ml,mut)


(* Subtyping *)

let (<:) { data=b1 } { data=b2 } =
  match b1,b2 with
    | UInt n, UInt m when n <= m -> true
    | Int n, Int m when n <= m -> true
    | Bool, Bool -> true
    | Num(k,s), Int n -> true
    | Int n, Num(k,s) -> true
    | Num(k,s), UInt n when not s -> true
    | UInt n, Num(k,s) when not s -> true
    | Num _, Num _ -> true
    | String, String -> true
    | _ -> false

let (=:) { data=b1 } { data=b2 } =
  match b1,b2 with
    | Num _, UInt _
    | Num _, Int _
    | UInt _, Num _
    | Int _, Num _ -> true
    | x, y when x = y -> true
    | _ -> false

let (<::) { data=ArrayAT(b1,lx1) } { data=ArrayAT(b2,lx2) } =
  let lxmatch =
    match lx1.data,lx2.data with
      | LIntLiteral n, LIntLiteral m when n = m -> true
      | LDynamic x, LDynamic y when x.data = y.data -> true
      | _ -> false in
    lxmatch && (b1 =: b2)

let join_bt p { data=b1 } { data=b2 } =
  let b' =
    match b1,b2 with
      | UInt n, UInt m -> UInt (max n m)
      | Int n, Int m -> Int (max n m)
      | Bool, Bool -> b1
      | Num(k,s), Int n -> b2
      | Int n, Num(k,s) -> b1
      | Num(k,s), UInt n -> b2
      | UInt n, Num(k,s) -> b1
      | String, String -> b1
      | Num(k1,s1), Num(k2,s2) -> Num(max k1 k2,s1 || s2) (* XXX max k1 k2 makes no sense *)
      | _ -> raise @@ cerr("type mismatch: " ^ show_base_type' b1 ^ " <> " ^ show_base_type' b2, p);
  in mkpos b'

let min_bt p { data=b1 } { data=b2 } =
  let b' =
    match b1,b2 with
      | UInt n, UInt m -> UInt (min n m)
      | Int n, Int m -> Int (min n m)
      | Num(k,s), Int n -> b2
      | Int n, Num(k,s) -> b1
      | Num(k,s), UInt n -> b2
      | UInt n, Num(k,s) -> b1
      | Num(k1,s1), Num(k2,s2) -> Num(max k1 k2,s1 || s2) (* XXX max k1 k2 makes no sense *)
      | _ -> raise @@ cerr("invalid types for min_bt: " ^ show_base_type' b1 ^ " <> " ^ show_base_type' b2, p);
  in mkpos b'

let meet_bt p { data=b1 } { data=b2 } =
  let b' =
    match b1,b2 with
      | UInt n, UInt m when n = m -> b1
      | Int n, Int m when n = m -> b1
      | Bool, Bool -> b1
      | Num(k,s), Int n -> b2
      | Int n, Num(k,s) -> b1
      | Num(k,s), UInt n when k >= 0 -> b2
      | UInt n, Num(k,s) when k >= 0 -> b1
      | String, String -> b1
      | Num(k1,s1), Num(k2,s2) -> Num(max k1 k2,s1 || s2)
      | _ -> raise @@ err(p)
  in mkpos b'

let (<$.) l1 l2 =
  match l1,l2 with
    | x, y when x = y -> true
    | Public, Secret -> true
    | _ -> false

let (+$.) l1 l2 =
  match l1,l2 with
    | Public, Public -> Public
    | Public, Secret -> Secret
    | Secret, Public -> Secret
    | Secret, Secret -> Secret

let (<$) { data=ml1 } { data=ml2 } =
  match ml1,ml2 with
    | Fixed x, Fixed y -> x <$. y
    | _ -> false

let join_ml p { data=ml1 } { data=ml2 } =
  let ml' =
    match ml1,ml2 with
      | Fixed x, Fixed y -> Fixed (x +$. y)
      | _ -> raise @@ err(p)
  in mkpos ml'

let (<:$) ty1 ty2 =
  match (is_array ty1),(is_array ty2) with
    | false, false ->
      let b1,ml1 = type_out ty1 in
      let b2,ml2 = type_out ty2 in
        (b1 <: b2) && (ml1 <$ ml2)
    | _ -> false

let join_ty' p ty1 ty2 =
  let b1,ml1 = type_out ty1 in
  let b2,ml2 = type_out ty2 in
  let b' = join_bt p b1 b2 in
  let ml' = join_ml p ml1 ml2 in
    BaseET(b', ml')

let (<*) m1 m2 =
  match m1,m2 with
    | Const, Mut -> false (* can't alias a const as a mut *)
    | _ -> true

let can_be_passed_to { pos=p; data=argty} {data=paramty} =
  match argty, paramty with
    | RefVT(_,_,m1), RefVT(_,_,m2) when m1.data <> m2.data -> false
    | RefVT(b1,l1,_), RefVT(b2,l2,_) ->
      (b1 <: b2) && (l1 <$ l2)
    | ArrayVT(a1,l1,m1), ArrayVT(a2,l2,m2) ->
      let ArrayAT(b1,lx1), ArrayAT(b2,lx2) = a1.data, a2.data in
      let lxmatch =
        match lx1.data, lx2.data with
          | _, LDynamic _ -> true
          | LIntLiteral n, LIntLiteral m when n = m -> true
          | _ -> false
      in
        (b1.data = b2.data) && lxmatch && (l1 <$ l2) && (m1.data = m2.data)

let (<:$*) (ty1,is_new_mem) ty2 =
  let ArrayET(a1,l1,m1) = ty1.data in
  let ArrayET(a2,l2,m2) = ty2.data in
  let ArrayAT(b1,lx1), ArrayAT(b2,lx2) = a1.data, a2.data in
  let lxmatch =
    match lx1.data, lx2.data with
      | _, LDynamic _ -> true
      | LIntLiteral n, LIntLiteral m when n = m -> true
      | _ -> false
  in
    (b1 <: b2) &&
    lxmatch &&
    (match m1.data, m2.data with
      | Const, Const -> l1 <$ l2
      | Mut, Const -> l1 <$ l2
      | Const, Mut -> is_new_mem && l1 <$ l2
      | Mut, Mut -> l1.data = l2.data
    )



(* Actual typechecking *)

let tc_unop' p op e =
  let b,ml = expr_to_types e in
    begin
      match op with
        | Ast.Neg ->
          if not (is_int b) then raise @@ err(p);
        | Ast.BitwiseNot ->
          if not (is_int b) then raise @@ err(p);
        | Ast.LogicalNot ->
          if not (is_bool b) then raise @@ err(p);
    end;
    begin
      match b.data with
        | Num(k,s) ->
          let n = k * if s then -1 else 1 in
            begin
              match op with
                | Ast.Neg        -> make_nlit p ( -n)
                | Ast.BitwiseNot -> make_nlit p ((-n) - 1)
            end
        | _ ->
          (UnOp(op, e), BaseET(b, ml))
    end

let tc_binop_check p op b1 b2 =
  match op with
    | Ast.Equal
    | Ast.NEqual ->
      if (is_bool b1 && not (is_bool b2))
      || (is_bool b2 && not (is_bool b1))
      then raise @@ err(p)
    | Ast.Plus
    | Ast.Minus
    | Ast.Multiply
    | Ast.GT
    | Ast.GTE
    | Ast.LT
    | Ast.LTE
    | Ast.BitwiseAnd
    | Ast.BitwiseOr
    | Ast.BitwiseXor
    | Ast.LeftShift
    | Ast.RightShift ->
      if not (is_int b1) || not (is_int b2) then raise @@ err(p)
    | Ast.LogicalAnd
    | Ast.LogicalOr ->
      if not (is_bool b1) || not (is_bool b2) then raise @@ err(p)

let tc_binop' p op e1 e2 =
  let b1,ml1 = expr_to_types e1 in
  let b2,ml2 = expr_to_types e2 in
    match b1.data, b2.data with
      | Num (k1,s1), Num (k2,s2) ->
        let n = k1 * if s1 then -1 else 1 in
        let m = k2 * if s2 then -1 else 1 in
          begin
            match op with
              | Ast.Plus       -> make_nlit p (n + m)
              | Ast.Minus      -> make_nlit p (n - m)
              | Ast.Multiply   -> make_nlit p (n * m)
              | Ast.BitwiseOr  -> make_nlit p (n lor m)
              | Ast.BitwiseXor -> make_nlit p (n lxor m)
              | Ast.BitwiseAnd -> make_nlit p (n land m)
              | Ast.Equal      -> make_blit p (n = m)
              | Ast.NEqual     -> make_blit p (n != m)
              | Ast.GT         -> make_blit p (n > m)
              | Ast.GTE        -> make_blit p (n >= m)
              | Ast.LT         -> make_blit p (n < m)
              | Ast.LTE        -> make_blit p (n <= m)
              | Ast.LeftShift  -> make_nlit p (n lsl m)
              | Ast.RightShift -> make_nlit p (n asr m)
          end
      | _ ->
        tc_binop_check p op b1 b2;
        let b' =
          match op with
            | Ast.Plus
            | Ast.Minus
            | Ast.Multiply
            | Ast.BitwiseOr
            | Ast.BitwiseXor
            | Ast.LogicalAnd
            | Ast.LogicalOr -> join_bt p b1 b2

            | Ast.BitwiseAnd -> min_bt p b1 b2

            | Ast.Equal
            | Ast.NEqual
            | Ast.GT
            | Ast.GTE
            | Ast.LT
            | Ast.LTE -> mkpos Bool

            | Ast.LeftShift
            | Ast.RightShift -> { b1 with pos=p }
        in
        let ml' = join_ml p ml1 ml2 in
          (BinOp(op, e1, e2), BaseET(b', ml'))

let params_all_refs_above rpc params =
  let rec checker n = function
    | [] -> -1
    | ({data=Param(_,{data=vty'}); pos=p}::params) ->
      begin
        match vty' with
          | RefVT(_,{data=Fixed l},{data=mut})
          | ArrayVT(_,{data=Fixed l},{data=mut}) ->
            if (mut != Mut) || (rpc <$. l)
            then (checker (n+1) params)
            else n
      end
  in
  checker 0 params

let rec lexprconv tc_ctx = pfunction
  | Ast.LExpression ({data=Ast.IntLiteral n}) ->
    LIntLiteral n
  | Ast.LExpression e ->
    let lenvt = mkpos RefVT(mkpos UInt 32, mkpos Fixed Public, mkpos Const) in
    let e' = tc_expr tc_ctx e in
    let len_var = mkpos (make_fresh "len") in
    let len = add_new_var tc_ctx.venv len_var lenvt in
      tc_ctx.add_stms := (BaseDec(len,lenvt,e')) :: !(tc_ctx.add_stms);
      LDynamic len
  | Ast.LUnspecified -> raise @@ err(p)

and atype_conv_fill tc_ctx lexpr' = pfunction
  | Ast.ArrayAT(bt,{data=LUnspecified}) ->
    ArrayAT(bconv bt, mkpos lexpr')
  | Ast.ArrayAT(bt,le) ->
    ArrayAT(bconv bt, lexprconv tc_ctx le)

and refvt_conv_fill tc_ctx lexpr' = pfunction
  | Ast.RefVT(b,l,m) ->
    RefVT(bconv b, mlconv l, mconv m)
  | Ast.ArrayVT(a,ml,m) ->
    ArrayVT(atype_conv_fill tc_ctx lexpr' a, mlconv ml, mconv m)

and tc_arg tc_ctx = pfunction
  | Ast.ByValue e ->
    begin
      match e.data with
        | Ast.Variable x ->
          let _,vty = Env.find_var tc_ctx.venv x in
            begin
              match vty.data with
                | RefVT _ -> ByValue (tc_expr tc_ctx e)
                | ArrayVT _ ->
                  let ae',_ = tc_arrayexpr tc_ctx (mkpos Ast.ArrayVar x) in
                  let (_,ArrayET(_,_,mut)) = ae'.data in
                    if not (mut.data <* Const) then raise @@ err(p);
                    ByArray(ae', mkpos Const)
            end
        | _ -> ByValue (tc_expr tc_ctx e)
    end
  | Ast.ByRef x ->
    let x',xref = Env.find_var tc_ctx.venv x in
      begin
        match xref.data with
          | RefVT _ -> ByRef x'
          | ArrayVT _ ->
            let ae',_ = tc_arrayexpr tc_ctx (mkpos Ast.ArrayVar x) in
            let (_,ArrayET(_,_,mut)) = ae'.data in
              if not (mut.data <* Mut) then raise @@ cerr("variable `" ^ x.data ^ "` is not mut; ", p);
              ByArray(ae', mkpos Mut)
      end
  | Ast.ByArray(arr_expr, mutability) ->
    let m' = mconv mutability in
    let ae',_ = tc_arrayexpr tc_ctx arr_expr in
    let (_,ArrayET(_,_,mut)) = ae'.data in
    if not (mut.data <* m'.data) then raise @@ cerr("array expression is not proper mutability; ", p);
    ByArray(ae', m')

and tc_args ~xf_args tc_ctx p params args =
  match params,args with
    | [], [] -> []
    | (param::params), (arg::args) ->
      let arg' = tc_arg tc_ctx arg in
      let argref = argtype_of tc_ctx.venv arg' in
      let Param(_,paramvt) = param.data in
        if not @@ can_be_passed_to argref paramvt then raise @@ err(arg'.pos);
        if param_is_ldynamic param && xf_args then
          let _::params = params in
          let ByArray({data=(_,atype')},_) = arg'.data in
          let lexpr' = aetype_to_lexpr' (mkpos atype') in
          let len =
            match lexpr' with
              | LIntLiteral n ->
                ByValue (mkpos (IntLiteral n, BaseET(mkpos Num(abs n,n < 0), mkpos Fixed Public)))
              | LDynamic lx ->
                ByValue (mkpos (Variable lx, BaseET(mkpos UInt 32, mkpos Fixed Public)))
          in
            arg' :: (mkpos len) :: tc_args ~xf_args tc_ctx p params args
        else
          arg' :: tc_args ~xf_args tc_ctx p params args
    | _ -> raise @@ cerr("mismatch in args vs params length", p)

and tc_expr tc_ctx = pfunction
  | Ast.True ->
    make_blit p true
  | Ast.False ->
    make_blit p false
  | Ast.IntLiteral n ->
    make_nlit p n
  | Ast.StringLiteral s ->
    (StringLiteral s, BaseET(mkpos String, mkpos Fixed Public))
  | Ast.Variable x ->
    let x',xref = Env.find_var tc_ctx.venv x in
      (Variable x', refvt_to_etype' xref)
  | Ast.ArrayGet(x,e) ->
    let x',xref = Env.find_var tc_ctx.venv x in
    let e' = tc_expr tc_ctx e in
      (ArrayGet(x',e'), refvt_to_betype' xref)
  | Ast.ArrayLen x ->
    (* XXX type should be size_t not uint32 *)
    let _,xref = Env.find_var tc_ctx.venv x in
    let lexpr = refvt_to_lexpr xref in
      begin
        match lexpr.data with
          | LIntLiteral n ->
            (IntLiteral n, BaseET(mkpos Num(abs n,n < 0), mkpos Fixed Public))
          | LDynamic len ->
            (Variable len, BaseET(mkpos UInt 32, mkpos Fixed Public))
      end
  | Ast.IntCast(b,e) ->
    let b' = bconv b in
      if not (is_int b') then raise @@ err(b'.pos);
    let e' = tc_expr tc_ctx e in
      if not (is_int (expr_to_btype e')) then raise @@ err(e'.pos);
    let ml = expr_to_ml e' in
      (IntCast(b',e'), BaseET(b',ml))
  | Ast.Declassify e ->
    let e' = tc_expr tc_ctx e in
      (Declassify e', BaseET(expr_to_btype e', mkpos Fixed Public))
  | Ast.UnOp(op,e) ->
    let e' = tc_expr tc_ctx e in
      tc_unop' p op e'
  | Ast.BinOp(op,e1,e2) ->
    let e1' = tc_expr tc_ctx e1 in
    let e2' = tc_expr tc_ctx e2 in
      tc_binop' p op e1' e2'
  | Ast.TernOp(e1,e2,e3) ->
    let e1' = tc_expr tc_ctx e1 in
      if not (is_bool (expr_to_btype e1')) then raise @@ err(e1'.pos);
    let e2' = tc_expr tc_ctx e2 in
    let e3' = tc_expr tc_ctx e3 in
      (TernOp(e1',e2',e3'), join_ty' p (type_of e2') (type_of e3'))
  | Ast.FnCall(f,args) ->
    let rpc = !(tc_ctx.rp) +$. tc_ctx.pc in
    begin
      match (Env.find_var tc_ctx.fenv f).data with
        | (FunDec(_,Some rty,params,_)) ->
          (* ensure no mut args lower than rp U pc *)
          (* e.g. fcall with public mut arg in a block where pc is Secret *)
          let earg_n = params_all_refs_above rpc params in
            if earg_n >= 0 then
              (let earg = List.nth args earg_n in
                 raise @@ err(earg.pos));
            let args' = tc_args ~xf_args:true tc_ctx p params args in
              (FnCall(f,args'), rty.data)
        | (CExtern(_,Some rty,params)) ->
          (* ensure no mut args lower than rp U pc *)
          (* e.g. fcall with public mut arg in a block where pc is Secret *)
          let earg_n = params_all_refs_above rpc params in
            if earg_n >= 0 then
              (let earg = List.nth args earg_n in
                 raise @@ err(earg.pos));
            let args' = tc_args ~xf_args:false tc_ctx p params args in
              (FnCall(f,args'), rty.data)
        | (DebugFunDec(_,Some rty,params)) ->
          let args' = tc_args ~xf_args:false tc_ctx p params args in
            DebugFnCall(f,args'), rty.data
    end

(* returns ((Tast.array_expr', Tast.ArrayET), is_new_memory) *)
and tc_arrayexpr' tc_ctx = xfunction
  | Ast.ArrayLit exprs ->
    (* XXX check that all expr types are compatible *)
    let exprs' = List.map (tc_expr tc_ctx) exprs in
    let b = expr_to_btype @@ List.hd exprs' in (* XXX should be join of all exprs' *)
    let at' = mkpos ArrayAT(b, mkpos LIntLiteral(List.length exprs')) in
      (ArrayLit exprs',
       ArrayET(at', mkpos Fixed Public (* XXX should be join of all exprs' *), mkpos Const)),
       true
  | Ast.ArrayVar x ->
    let x',xref = Env.find_var tc_ctx.venv x in
      (ArrayVar x', refvt_to_etype' xref), false
  | Ast.ArrayZeros lexpr ->
    let b = mkpos Num(0, false) in
    let lexpr' = lexprconv tc_ctx lexpr in
    let at' = mkpos ArrayAT(b, lexpr') in
    (ArrayZeros lexpr', ArrayET(at', mkpos Fixed Public, mkpos Const)), true
  | Ast.ArrayCopy x ->
    let x',vt = Env.find_var tc_ctx.venv x in
    let ae' = refvt_to_etype' vt in
      (ArrayCopy x', aetype_update_mut' (mkpos Mut) ae'), true
  | Ast.ArrayView(x,e,lexpr) ->
    let e' = tc_expr tc_ctx e in
    let lexpr' = lexprconv tc_ctx lexpr in
    let x',vt = Env.find_var tc_ctx.venv x in
    let ae = refvt_to_etype vt in
    let ae' = aetype_update_lexpr' lexpr'.data ae in
      (ArrayView(x',e',lexpr'), ae'), false
  | Ast.ArrayComp(b,lexpr,x,e) ->
    let b' = bconv b in
    let lexpr' = lexprconv tc_ctx lexpr in
    let e' = tc_expr tc_ctx e in
    let ae = ArrayET(mkpos ArrayAT(b', lexpr'), expr_to_ml e', mkpos Mut) in
      (ArrayComp(b',lexpr',x,e'), ae), true
and tc_arrayexpr tc_ctx pa =
  let ae', is_mem_new = tc_arrayexpr' tc_ctx pa in
    make_ast pa.pos ae', is_mem_new

let rec tc_stm' tc_ctx = xfunction

  | Ast.BaseDec(x,vt,e) ->
    let e' = tc_expr tc_ctx e in
    let ety = type_of e' in
    let vt' = refvt_conv vt in
    let xty = refvt_to_etype vt' in
      if not (ety <:$ xty) then
        raise @@ cerr("expression of type `" ^ ps_ety ety ^ "` cannot be assigned to variable of type `" ^ ps_ety xty ^ "`", p);
      let x' = add_new_var tc_ctx.venv x vt' in
        [BaseDec(x',vt',e')]

  | Ast.BaseAssign(x,e) ->
    let e' = tc_expr tc_ctx e in
    let x',vt = Env.find_var tc_ctx.venv x in
    let b,{data=Fixed l},m = refvt_type_out vt in
      (* check that x is indeed mutable *)
      if m.data <> Mut then raise @@ cerr("variable `" ^ x.data ^ "` is not mutable; ", p);

      (* check that rp U pc is <= label of x *)
      if not ((!(tc_ctx.rp) +$. tc_ctx.pc) <$. l) then
        raise @@ cerr("cannot assign to " ^ ps_label' p l ^ " variable when program context is " ^ ps_label' p (!(tc_ctx.rp) +$. tc_ctx.pc), p);

      (* check that labeled type of e is <= labeled type of x *)
      let ety = type_of e' in
      let xty = refvt_to_etype vt in
        if not (ety <:$ xty) then
          raise @@ cerr("expression of type `" ^ ps_ety ety ^ "` cannot be assigned to variable of type `" ^ ps_ety xty ^ "`", p);

      [BaseAssign(x',e')]

  | Ast.ArrayDec(x,vt,ae) ->
    let ae',is_new_mem = tc_arrayexpr tc_ctx ae in
    let aty = atype_of ae' in
    (* if vt is LUnspecified then take it from aty *)
    let ae_lexpr' = aetype_to_lexpr' aty in
    let vt' = refvt_conv_fill tc_ctx ae_lexpr' vt in
    let xty = refvt_to_etype vt' in
      if not ((aty,is_new_mem) <:$* xty) then
        raise @@ cerr("array of type `" ^ ps_ety aty ^ "` cannot be assigned to variable of type `" ^ ps_ety xty ^ "`", p);

      let x' = add_new_var tc_ctx.venv x vt' in
        [ArrayDec(x',vt',ae')]

  | Ast.ArrayAssign(x,n,e) ->
    let n' = tc_expr tc_ctx n in
    let e' = tc_expr tc_ctx e in
    let x',vt = Env.find_var tc_ctx.venv x in
    let b,{data=Fixed l},m = refvt_type_out vt in
      (* check that x is indeed mutable *)
      if m.data <> Mut then raise @@ cerr("array `" ^ x.data ^ "` is not mutable; ", p);

      (* check that rp U pc is <= label of x *)
      if not ((!(tc_ctx.rp) +$. tc_ctx.pc) <$. l) then
        raise @@ cerr("cannot assign into " ^ ps_label' p l ^ " array when program context is " ^ ps_label' p (!(tc_ctx.rp) +$. tc_ctx.pc), p);

      (* check that labeled type of e is <= labeled type of x *)
      let ety = type_of e' in
      let xty = refvt_to_betype vt in
        if not (ety <:$ xty) then
          raise @@ cerr("expression of type `" ^ ps_ety ety ^ "` cannot be assigned into array with elements of type `" ^ ps_ety xty ^ "`", p);

      (* TODO check that n' won't be out-of-bounds *)
      [ArrayAssign(x',n',e')]

  | Ast.If(cond,thenstms,elsestms) ->
    let cond' = tc_expr tc_ctx cond in
    let {data=Fixed l} = expr_to_ml cond' in
    (* TODO check that cond' is bool *)
    let pc' = tc_ctx.pc +$. l in
    let tc_ctx1 = { tc_ctx with pc=pc'; rp=ref !(tc_ctx.rp); venv=(Env.sub_env tc_ctx.venv) } in
    let tc_ctx2 = { tc_ctx with pc=pc'; rp=ref !(tc_ctx.rp); venv=(Env.sub_env tc_ctx.venv) } in
    let thenstms' = tc_block tc_ctx1 thenstms in
    let elsestms' = tc_block tc_ctx2 elsestms in
      tc_ctx.rp := !(tc_ctx1.rp) +$. !(tc_ctx2.rp);
      [If(cond',thenstms',elsestms')]

  | Ast.For(i,ity,lo,hi,stms) ->
    let ity' = bconv ity in
    let lo' = tc_expr tc_ctx lo in
    let hi' = tc_expr tc_ctx hi in
    (* TODO check types and labels *)
    let venv' = Env.sub_env tc_ctx.venv in
    let i' = add_new_var venv' i (mkpos RefVT(ity',mkpos Fixed Public,mkpos Const)) in
      let tc_ctx' = { tc_ctx with venv=venv' } in
      let stms' = tc_block tc_ctx' stms in
        [For(i',ity',lo',hi',stms')]

  | Ast.VoidFnCall(f,args) ->
    let rpc = !(tc_ctx.rp) +$. tc_ctx.pc in
      begin
        match (Env.find_var tc_ctx.fenv f).data with
          | (FunDec(_,_,params,_)) ->
            (* ensure no mut args lower than rp U pc *)
            (* e.g. fcall with public mut arg in a block where pc is Secret *)
            let earg_n = params_all_refs_above rpc params in
              if earg_n >= 0 then
                (let earg = List.nth args earg_n in
                   raise @@ err(earg.pos));

              let args' = tc_args ~xf_args:true tc_ctx p params args in
                [VoidFnCall(f,args')]
          | (CExtern(_,_,params)) ->
            (* ensure no mut args lower than rp U pc *)
            (* e.g. fcall with public mut arg in a block where pc is Secret *)
            let earg_n = params_all_refs_above rpc params in
              if earg_n >= 0 then
                (let earg = List.nth args earg_n in
                   raise @@ err(earg.pos));

              let args' = tc_args ~xf_args:false tc_ctx p params args in
                [VoidFnCall(f,args')]
          | (DebugFunDec(_,_,params)) ->
            let args' = tc_args ~xf_args:false tc_ctx p params args in
              [DebugVoidFnCall(f,args')]
      end

  | Ast.Return e ->
    let e' = tc_expr tc_ctx e in
      (* TODO check type *)
      tc_ctx.rp := !(tc_ctx.rp) +$. tc_ctx.pc;
      [Return e']

  | Ast.VoidReturn ->
    (* TODO check that fn is indeed void *)
    [VoidReturn]
and tc_stm tc_ctx pa =
  List.map
    (make_ast pa.pos)
    (let stms = tc_stm' tc_ctx pa in
     let stms' = (List.rev !(tc_ctx.add_stms)) @ stms in
       tc_ctx.add_stms := [];
       stms')

and tc_block tc_ctx stms =
  let stms' = List.flatten @@ List.map (tc_stm tc_ctx) stms in
    (tc_ctx.venv, stms')

let tc_param' xf_param = xfunction
  | Ast.Param(x,vty) ->
    let len = "__" ^ x.data ^ "_len" in
    let lexpr' = LDynamic(mkpos len) in
    (* the lexpr will only get used if vty is LUnspecified *)
      (* XXX the following line is a total hack *)
      let fake_hacky_useless_tc_ctx = { rp=ref Public; pc=Public; venv=Env.new_env (); fenv=Env.new_env (); add_stms=ref [] } in
    let refvt = refvt_conv_fill fake_hacky_useless_tc_ctx lexpr' vty in
    let param = Param(x,refvt) in
    let lexpr = refvt_to_lexpr_option refvt in
      param :: (match lexpr with
                 | Some LDynamic len when xf_param ->
                   let lenvt = mkpos RefVT(mkpos UInt 32, mkpos Fixed Public, mkpos Const) in
                     [Param(len, lenvt)]
                 | _ -> [])
let tc_param xf_param pa = List.map (make_ast pa.pos) (tc_param' xf_param pa)

let tc_fdec' fpos fenv = function
  | Ast.FunDec(f,rt,params,stms) ->
    let rt' =
      match rt with
        | Some rty -> Some(etype_conv rty)
        | None -> None
    in
    let params' = List.flatten @@ List.map (tc_param true) params in
    let venv = Env.new_env () in
      List.iter (fun {data=Param(name,vty)} ->
                  let entry = (name,vty) in
                    Env.add_var venv name entry)
        params';
      let tc_ctx = { rp=ref Public; pc=Public; venv; fenv; add_stms=ref [] } in
      let rec final_stmt_rets stms =
        begin
          match List.rev stms with
            | [] -> false
            | s::ss ->
              begin
                match s.data with
                  | Ast.Return _
                  | Ast.VoidReturn -> true
                  | Ast.For(_,_,_,_,fstms) ->
                    final_stmt_rets fstms
                  | Ast.If(_,tstms,fstms) ->
                    (final_stmt_rets tstms) && (final_stmt_rets fstms)
                  | _ -> false
              end
        end in
      let stms' = if not (final_stmt_rets stms)
        then stms @ [make_ast fpos Ast.VoidReturn]
        else stms
      in
        FunDec(f,rt',params',tc_block tc_ctx stms')
  | Ast.CExtern(f,rt,params) ->
    let rt' =
      match rt with
        | Some rty -> Some(etype_conv rty)
        | None -> None
    in
    let params' = List.flatten @@ List.map (tc_param false) params in
    let venv = Env.new_env () in
      List.iter (fun {data=Param(name,vty)} ->
                  let entry = (name,vty) in
                    Env.add_var venv name entry)
        params';
      CExtern(f,rt',params')
let tc_fdec fenv = xfunction
  | Ast.FunDec(f,_,_,_)
  | Ast.CExtern(f,_,_) as fdec ->
    let fdec' = mkpos tc_fdec' p fenv fdec in
      Env.add_var fenv f fdec';
      fdec'

let tc_module (Ast.Module fdecs) =
  let fenv = Debugfun.make_fenv () in
  let ret = Module (fenv, List.map (tc_fdec fenv) fdecs) in
    ret
