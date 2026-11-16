// HeavyOptimizerFrontend::UpdateBranchTargetsAfterSplit(addr=rsi, old_bb=rdx, new_bb=rcx), this=rdi,
// for libndk_translation.so build-id 553ba82b76bb5a11fd1d67b2c7e01b75 (at 0xd62a0, 0xb0 bytes).
// branch_targets_: libc++ std::map<GuestAddr, pair<bb, optional<insn iterator>>> at this+0x20
// (begin node +0x20, root +0x28); node: left +0, right +8, parent +0x10, key +0x20, bb +0x28, iterator +0x30.
    .intel_syntax noprefix
    .text
    .globl update_branch_targets
update_branch_targets:
    lea  r10, [rdi + 0x28]
    mov  r8, [r10]
    mov  rax, r10
find:
    test r8, r8
    jz   found
    cmp  [r8 + 0x20], rsi
    jb   find_right
    mov  rax, r8
    mov  r8, [r8]
    jmp  find
find_right:
    mov  r8, [r8 + 8]
    jmp  find
found:
    cmp  rax, r10
    je   done
    cmp  [rax + 0x20], rsi
    jne  done
    // a guest NOP emits no code, so it shares the next instruction's position; without this its stale
    // entry makes SplitBasicBlock walk another block's list forever
    mov  r11, [rax + 0x30]
    mov  r9, rax
back:
    cmp  r9, [rdi + 0x20]
    je   forward
    mov  r8, [r9]
    test r8, r8
    jz   back_up
back_down:
    mov  r9, r8
    mov  r8, [r8 + 8]
    test r8, r8
    jnz  back_down
    jmp  back_check
back_up:
    mov  r8, [r9 + 0x10]
    cmp  [r8], r9
    mov  r9, r8
    je   back_up
back_check:
    cmp  [r9 + 0x28], rdx
    jne  forward
    cmp  [r9 + 0x30], r11
    jne  forward
    mov  [r9 + 0x28], rcx
    jmp  back
forward:
    cmp  [rax + 0x28], rdx
    jne  done
    mov  [rax + 0x28], rcx
    mov  r8, [rax + 8]
    test r8, r8
    jz   forward_up
forward_down:
    mov  rax, r8
    mov  r8, [r8]
    test r8, r8
    jnz  forward_down
    jmp  forward_next
forward_up:
    mov  r8, [rax + 0x10]
    cmp  [r8], rax
    mov  rax, r8
    jne  forward_up
forward_next:
    cmp  rax, r10
    jne  forward
done:
    ret
