;; AotAnywhere addition: MSVC ARM64 /GS stack-cookie push/pop helper pair.
;;
;; Kept separate from the vendored aotcrtstub_arm64.asm (imported unmodified
;; from awakecoding/runtime's experimental/nativeaot-crt-free branch) so the
;; two can be diffed/re-synced independently.
;;
;; The MSVC ARM64 code generator emits calls to __security_push_cookie /
;; __security_pop_cookie (rather than the fixed-offset inline cookie check
;; used elsewhere) around frames that combine /GS with a dynamic stack
;; allocation. The real implementations live in the proprietary
;; libcpmt.lib/oldnames.lib, which have no redistributable counterpart; this
;; reproduces their verified disassembly (MSVC 14.x crt/arm64/secpushpop.asm):
;; a 16-byte slot is reserved and the epilogue helper recomputes and compares
;; the same (sp - __security_cookie) value stashed by the prologue helper,
;; using x16/x17 (IP0/IP1) as the only scratch registers guaranteed free at
;; these call sites.

        AREA    |.text|, CODE, READONLY

        IMPORT  __security_cookie

        EXPORT  __security_push_cookie
        EXPORT  __security_pop_cookie

__security_push_cookie PROC
        sub     sp, sp, #16
        adrp    x17, __security_cookie
        ldr     x17, [x17, __security_cookie]
        sub     x17, sp, x17
        str     x17, [sp, #8]
        ret
__security_push_cookie ENDP

__security_pop_cookie PROC
        adrp    x17, __security_cookie
        ldr     x16, [sp, #8]
        ldr     x17, [x17, __security_cookie]
        sub     x16, sp, x16
        cmp     x16, x17
        b.ne    AotCrtCookiePopFailure
        add     sp, sp, #16
        ret
AotCrtCookiePopFailure
        brk     #0xF001
__security_pop_cookie ENDP

        END
