// Licensed to the .NET Foundation under one or more agreements.
// The .NET Foundation licenses this file to you under the MIT license.

//
// aotcrtstub-extra - additional MSVC CRT support symbols referenced by the
// precompiled NativeAOT bootstrapper/runtime objects that the vendored
// aotcrtstub.c/aotcrtstubcpp.cpp (imported unmodified from
// awakecoding/runtime's experimental/nativeaot-crt-free branch) do not
// provide. This file is authored by AotAnywhere itself, kept separate from
// the vendored sources so the two can be diffed/re-synced independently.
//
// MSVC's x86_64 code generator always inlines the _Interlocked* intrinsics
// (no external reference remains), but its ARM64 code generator emits real
// out-of-line calls to them; the ARM64 NativeAOT bootstrapper objects
// (e.g. runtime.win-arm64.microsoft.dotnet.ilcompiler's bootstrapper.obj)
// therefore reference these symbols and expect real definitions from
// oldnames.lib/libcpmt.lib, which are proprietary MSVC CRT-compatibility
// libraries with no redistributable counterpart. Clang's __atomic_* GNU
// builtins are available regardless of clang-cl's MSVC-compatible frontend
// mode and compile to the same lock-free ARM64 instruction sequences, so
// they are used here instead of a real implementation.
//

#if defined(_M_ARM64) || defined(__aarch64__)

//
// These are deliberately NOT named _InterlockedXxx: clang-cl recognizes each
// _InterlockedXxx name as a built-in MSVC-compatibility intrinsic and refuses
// to compile a translation unit that defines a real function under that name
// ("definition of builtin function"), even under -fno-builtin. The real
// _InterlockedXxx external symbols are instead provided by tiny tail-branch
// trampolines in aotcrtstub-extra-arm64.asm that jump straight into these
// functions - register-preserving, so it's a transparent passthrough.
//

long AotCrtInterlockedAnd(long volatile* p, long v) { return __atomic_fetch_and(p, v, __ATOMIC_SEQ_CST); }
long AotCrtInterlockedOr(long volatile* p, long v) { return __atomic_fetch_or(p, v, __ATOMIC_SEQ_CST); }
long AotCrtInterlockedXor(long volatile* p, long v) { return __atomic_fetch_xor(p, v, __ATOMIC_SEQ_CST); }
long AotCrtInterlockedExchange(long volatile* p, long v) { return __atomic_exchange_n(p, v, __ATOMIC_SEQ_CST); }
long AotCrtInterlockedExchangeAdd(long volatile* p, long v) { return __atomic_fetch_add(p, v, __ATOMIC_SEQ_CST); }
long AotCrtInterlockedIncrement(long volatile* p) { return __atomic_add_fetch(p, 1, __ATOMIC_SEQ_CST); }
long AotCrtInterlockedDecrement(long volatile* p) { return __atomic_sub_fetch(p, 1, __ATOMIC_SEQ_CST); }

long AotCrtInterlockedCompareExchange(long volatile* p, long exch, long cmp)
{
    __atomic_compare_exchange_n(p, &cmp, exch, 0, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST);
    return cmp;
}

long long AotCrtInterlockedExchange64(long long volatile* p, long long v) { return __atomic_exchange_n(p, v, __ATOMIC_SEQ_CST); }
long long AotCrtInterlockedExchangeAdd64(long long volatile* p, long long v) { return __atomic_fetch_add(p, v, __ATOMIC_SEQ_CST); }
long long AotCrtInterlockedAnd64(long long volatile* p, long long v) { return __atomic_fetch_and(p, v, __ATOMIC_SEQ_CST); }
long long AotCrtInterlockedOr64(long long volatile* p, long long v) { return __atomic_fetch_or(p, v, __ATOMIC_SEQ_CST); }
long long AotCrtInterlockedIncrement64(long long volatile* p) { return __atomic_add_fetch(p, 1, __ATOMIC_SEQ_CST); }
long long AotCrtInterlockedDecrement64(long long volatile* p) { return __atomic_sub_fetch(p, 1, __ATOMIC_SEQ_CST); }

long long AotCrtInterlockedCompareExchange64(long long volatile* p, long long exch, long long cmp)
{
    __atomic_compare_exchange_n(p, &cmp, exch, 0, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST);
    return cmp;
}

void* AotCrtInterlockedExchangePointer(void* volatile* p, void* v) { return __atomic_exchange_n(p, v, __ATOMIC_SEQ_CST); }

void* AotCrtInterlockedCompareExchangePointer(void* volatile* p, void* exch, void* cmp)
{
    __atomic_compare_exchange_n(p, &cmp, exch, 0, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST);
    return cmp;
}

unsigned char AotCrtInterlockedCompareExchange128(long long volatile* dst, long long exchHigh, long long exchLow, long long* comparand)
{
    unsigned __int128 cmp = ((unsigned __int128)(unsigned long long)comparand[1] << 64) | (unsigned long long)comparand[0];
    unsigned __int128 exch = ((unsigned __int128)(unsigned long long)exchHigh << 64) | (unsigned long long)exchLow;
    unsigned __int128 old = cmp;
    int ok = __atomic_compare_exchange_n((unsigned __int128*)dst, &old, exch, 0, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST);
    comparand[0] = (long long)(unsigned long long)old;
    comparand[1] = (long long)(unsigned long long)(old >> 64);
    return (unsigned char)ok;
}

#endif
