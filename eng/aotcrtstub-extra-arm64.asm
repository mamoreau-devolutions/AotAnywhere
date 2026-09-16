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

;; The real _InterlockedXxx bodies live in aotcrtstub-extra.c under
;; AotCrtInterlockedXxx names: clang-cl recognizes the _InterlockedXxx names
;; themselves as built-in MSVC-compatibility intrinsics and refuses to
;; compile a C definition under those names. A plain unconditional branch
;; (not a call) is a transparent tail-passthrough here: it touches no
;; registers of its own, so every argument register and LR are exactly as
;; the original caller of _InterlockedXxx left them, and the target
;; function's "ret" returns straight to that original caller.

        IMPORT  AotCrtInterlockedAnd
        IMPORT  AotCrtInterlockedOr
        IMPORT  AotCrtInterlockedXor
        IMPORT  AotCrtInterlockedExchange
        IMPORT  AotCrtInterlockedExchangeAdd
        IMPORT  AotCrtInterlockedIncrement
        IMPORT  AotCrtInterlockedDecrement
        IMPORT  AotCrtInterlockedCompareExchange
        IMPORT  AotCrtInterlockedExchange64
        IMPORT  AotCrtInterlockedExchangeAdd64
        IMPORT  AotCrtInterlockedAnd64
        IMPORT  AotCrtInterlockedOr64
        IMPORT  AotCrtInterlockedIncrement64
        IMPORT  AotCrtInterlockedDecrement64
        IMPORT  AotCrtInterlockedCompareExchange64
        IMPORT  AotCrtInterlockedExchangePointer
        IMPORT  AotCrtInterlockedCompareExchangePointer
        IMPORT  AotCrtInterlockedCompareExchange128

        EXPORT  _InterlockedAnd
        EXPORT  _InterlockedOr
        EXPORT  _InterlockedXor
        EXPORT  _InterlockedExchange
        EXPORT  _InterlockedExchangeAdd
        EXPORT  _InterlockedIncrement
        EXPORT  _InterlockedDecrement
        EXPORT  _InterlockedCompareExchange
        EXPORT  _InterlockedExchange64
        EXPORT  _InterlockedExchangeAdd64
        EXPORT  _InterlockedAnd64
        EXPORT  _InterlockedOr64
        EXPORT  _InterlockedIncrement64
        EXPORT  _InterlockedDecrement64
        EXPORT  _InterlockedCompareExchange64
        EXPORT  _InterlockedExchangePointer
        EXPORT  _InterlockedCompareExchangePointer
        EXPORT  _InterlockedCompareExchange128

_InterlockedAnd PROC
        b       AotCrtInterlockedAnd
_InterlockedAnd ENDP

_InterlockedOr PROC
        b       AotCrtInterlockedOr
_InterlockedOr ENDP

_InterlockedXor PROC
        b       AotCrtInterlockedXor
_InterlockedXor ENDP

_InterlockedExchange PROC
        b       AotCrtInterlockedExchange
_InterlockedExchange ENDP

_InterlockedExchangeAdd PROC
        b       AotCrtInterlockedExchangeAdd
_InterlockedExchangeAdd ENDP

_InterlockedIncrement PROC
        b       AotCrtInterlockedIncrement
_InterlockedIncrement ENDP

_InterlockedDecrement PROC
        b       AotCrtInterlockedDecrement
_InterlockedDecrement ENDP

_InterlockedCompareExchange PROC
        b       AotCrtInterlockedCompareExchange
_InterlockedCompareExchange ENDP

_InterlockedExchange64 PROC
        b       AotCrtInterlockedExchange64
_InterlockedExchange64 ENDP

_InterlockedExchangeAdd64 PROC
        b       AotCrtInterlockedExchangeAdd64
_InterlockedExchangeAdd64 ENDP

_InterlockedAnd64 PROC
        b       AotCrtInterlockedAnd64
_InterlockedAnd64 ENDP

_InterlockedOr64 PROC
        b       AotCrtInterlockedOr64
_InterlockedOr64 ENDP

_InterlockedIncrement64 PROC
        b       AotCrtInterlockedIncrement64
_InterlockedIncrement64 ENDP

_InterlockedDecrement64 PROC
        b       AotCrtInterlockedDecrement64
_InterlockedDecrement64 ENDP

_InterlockedCompareExchange64 PROC
        b       AotCrtInterlockedCompareExchange64
_InterlockedCompareExchange64 ENDP

_InterlockedExchangePointer PROC
        b       AotCrtInterlockedExchangePointer
_InterlockedExchangePointer ENDP

_InterlockedCompareExchangePointer PROC
        b       AotCrtInterlockedCompareExchangePointer
_InterlockedCompareExchangePointer ENDP

_InterlockedCompareExchange128 PROC
        b       AotCrtInterlockedCompareExchange128
_InterlockedCompareExchange128 ENDP

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
