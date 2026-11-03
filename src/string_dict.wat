(module
   (@if $portable-int
   (@then
      (import "env" "int_val_32_exn"
         (func $int_val_32_exn (param (ref eq)) (param (ref eq)) (result i32)))
      (import "env" "caml_copy_nativeint"
         (func $caml_copy_nativeint (param i64) (result (ref eq))))
      (import "env" "Nativeint_val"
         (func $Nativeint_val (param (ref eq)) (result i64)))
   )
   (@else
      (import "env" "caml_copy_nativeint"
         (func $caml_copy_nativeint (param i32) (result (ref eq))))
      (import "env" "Nativeint_val"
         (func $Nativeint_val (param (ref eq)) (result i32)))
   ))
   (type $string (array (mut i8)))
   (type $bytes (array (mut i8)))
   (type $block (array (mut (ref eq))))
   (type $int_array (array (mut i32)))

   (@string $sd_offset "Base_string_dict: offset out of range")

   (func (export "Base_string_dict_blocks_of_string")
      (param (ref eq)) (result (ref eq))
      (local.get 0))

   (func $get_block
      (param $blocks (ref $string)) (param $offset i32) (result i32)
      (local $len i32) (local $res i32)
      ;; We consider strings as sequences of 4 bytes, padded at the
      ;; end by 0x80 followed by as many 0x00 as necessary
      (local.set $offset (i32.shl (local.get $offset) (i32.const 2)))
      (local.set $res (i32.const 0x80))
      (block $0_bytes
       (block $1_byte
        (block $2_bytes
         (block $3_bytes
          (block $4_bytes
           (br_table $0_bytes $1_byte $2_bytes $3_bytes $4_bytes
              (i32.sub (array.len (local.get $blocks)) (local.get $offset))))
          (return
             (i32.or
                (i32.or
                   (array.get_u $string (local.get $blocks) (local.get $offset))
                   (i32.shl (array.get_u $string (local.get $blocks)
                               (i32.add (local.get $offset) (i32.const 1)))
                            (i32.const 8)))
                (i32.or
                   (i32.shl (array.get_u $string (local.get $blocks)
                               (i32.add (local.get $offset) (i32.const 2)))
                            (i32.const 16))
                   (i32.shl (array.get_u $string (local.get $blocks)
                               (i32.add (local.get $offset) (i32.const 3)))
                            (i32.const 24))))))
         ;; 3 bytes
         (local.set $res
            (i32.or (i32.shl (local.get $res) (i32.const 8))
               (array.get_u $string (local.get $blocks)
                        (i32.add (local.get $offset) (i32.const 2))))))
        ;; 2 bytes
        (local.set $res
           (i32.or (i32.shl (local.get $res) (i32.const 8))
              (array.get_u $string (local.get $blocks)
                       (i32.add (local.get $offset) (i32.const 1))))))
       ;; 1 bytes
       (local.set $res
          (i32.or (i32.shl (local.get $res) (i32.const 8))
             (array.get_u $string (local.get $blocks) (local.get $offset)))))
      ;; 0 bytes
      (local.get $res))

   (func (export "Base_string_dict_get_block")
      (param $vblocks (ref eq)) (param $voffset (ref eq)) (result (ref eq))
      (local $blocks (ref $string))
      (local $offset i32) (local $len i32) (local $res i32)
      (local.set $blocks (ref.cast (ref $string) (local.get $vblocks)))
      (local.set $offset (@if $portable-int
                         (@then
                            (call $int_val_32_exn (local.get $voffset)
                               (global.get $sd_offset)))
                         (@else
                            (i31.get_s
                               (ref.cast (ref i31) (local.get $voffset))))
                         ))
      (@if $portable-int
      (@then
         ;; Sign-extend: blocks are compared *signed* both by
         ;; [Base_string_dict_find]'s [i32.lt_s]/[i32.gt_s] below and by
         ;; [Nativeint.compare] on the OCaml side (which sorts the keys at
         ;; construction time), so the 64-bit image must preserve the signed
         ;; 32-bit order.
         (return_call $caml_copy_nativeint
            (i64.extend_i32_s
               (call $get_block (local.get $blocks) (local.get $offset)))))
      (@else
         (return_call $caml_copy_nativeint
            (call $get_block (local.get $blocks) (local.get $offset))))
      ))

   (func $num_blocks (param $blocks (ref $string)) (result i32)
      (i32.shr_u (i32.add (array.len (local.get $blocks)) (i32.const 4))
         (i32.const 2)))

   (func (export "Base_string_dict_num_blocks")
      (param $blocks (ref eq)) (result (ref eq))
      (ref.i31 (call $num_blocks (ref.cast (ref $string) (local.get $blocks)))))

   (func (export "Base_string_dict_make_blocks")
      (param $vblocks (ref eq)) (result (ref eq))
      (local $blocks (ref $block))
      (local $res (ref $int_array))
      (local $len i32) (local $i i32)
      (local.set $blocks (ref.cast (ref $block) (local.get $vblocks)))
      (local.set $len (i32.sub (array.len (local.get $blocks)) (i32.const 1)))
      (local.set $res (array.new $int_array (i32.const 0) (local.get $len)))
      (loop $loop
         (if (i32.lt_u (local.get $i) (local.get $len))
            (then
               (@if $portable-int
               (@then
                  (array.set $int_array (local.get $res) (local.get $i)
                     (i32.wrap_i64
                        (call $Nativeint_val
                           (array.get $block (local.get $blocks)
                              (i32.add (local.get $i) (i32.const 1)))))))
               (@else
                  (array.set $int_array (local.get $res) (local.get $i)
                     (call $Nativeint_val
                        (array.get $block (local.get $blocks)
                           (i32.add (local.get $i) (i32.const 1)))))
               ))
               (local.set $i (i32.add (local.get $i) (i32.const 1)))
               (br $loop))))
      (local.get $res))

   (func (export "Base_string_dict_find")
      (param $vt (ref eq)) (param $vkey (ref eq)) (result (ref eq))
      (local $t (ref $block)) (local $key (ref $string))
      (local $keys (ref $int_array))
      (local $num_blocks i32) (local $i i32)
      (local $input_block i32) (local $block i32)
      (local $a i32) (local $b i32) (local $c i32)
      (local.set $t (ref.cast (ref $block) (local.get $vt)))
      (local.set $key (ref.cast (ref $string) (local.get $vkey)))
      (local.set $num_blocks (call $num_blocks (local.get $key)))
      (loop $outer
         (if (i32.lt_u (local.get $i) (local.get $num_blocks))
            (then
               (local.set $input_block
                  (call $get_block (local.get $key) (local.get $i)))
               (local.set $i (i32.add (local.get $i) (i32.const 1)))
               (local.set $keys
                  (ref.cast (ref $int_array)
                     (array.get $block (local.get $t) (i32.const 2))))
               (local.set $a (i32.const 0))
               (local.set $b
                  ;; Dict block field written by [String_dict]; always an [i31].
                  ;; lint-ignore-start manual-portability-handling-unsafe
                  (i31.get_s
                     (ref.cast (ref i31)
                        (array.get $block (local.get $t) (i32.const 1)))))
                  ;; lint-ignore-end manual-portability-handling-unsafe
               (if (i32.eq (local.get $b) (i32.const 1))
                  (then
                     (if (i32.eq (local.get $input_block)
                            (array.get $int_array (local.get $keys)
                               (i32.const 0)))
                        (then
                           (local.set $t
                              (ref.cast (ref $block)
                                 (array.get $block
                                    (ref.cast (ref $block)
                                       (array.get $block (local.get $t)
                                          (i32.const 3)))
                                    (i32.const 1))))
                           (br $outer))
                        (else
                           (return (ref.i31 (i32.const 0))))))
                  (else
                     (loop $inner
                        (if (i32.ge_u (local.get $a) (local.get $b))
                           (then (return (ref.i31 (i32.const 0)))))
                        (local.set $c
                           (i32.shr_u
                              (i32.add (local.get $a) (local.get $b))
                              (i32.const 1)))
                        (local.set $block
                           (array.get $int_array (local.get $keys)
                              (local.get $c)))
                        (if (i32.lt_s (local.get $input_block)
                               (local.get $block))
                           (then
                              (local.set $b (local.get $c)))
                        (else (if (i32.gt_s (local.get $input_block)
                                     (local.get $block))
                           (then
                              (local.set $a
                                 (i32.add (local.get $c) (i32.const 1))))
                        (else
                           (local.set $t
                              (ref.cast (ref $block)
                                 (array.get $block
                                    (ref.cast (ref $block)
                                       (array.get $block (local.get $t)
                                          (i32.const 3)))
                                    (i32.add (local.get $c) (i32.const 1)))))
                           (br $outer)))))
                        (br $inner)))))))
      (array.get $block (local.get $t) (i32.const 4)))
)
