// Replaces ResolveJumps' inlined UpdateBranchTargetsAfterSplit (0xd59a0..0xd5a2e) with a call to the fixed
// out-of-line copy. Live here: rax = new bb (from SplitBasicBlock), [rsp] = old bb, r12 = target,
// [rsp+8] = this; 0xd5a2e expects rax = new bb.
    .intel_syntax noprefix
    .text
    .set BASE, 0xd59a0
start:
    mov  rsi, r12
    mov  rdx, [rsp]
    mov  rcx, rax
    mov  r12, rax
    mov  rdi, [rsp + 8]
    .byte 0xe8
    .long 0xd62a0 - BASE - (. - start) - 4
    mov  rax, r12
    .byte 0xe9
    .long 0xd5a2e - BASE - (. - start) - 4
