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

long _InterlockedAnd(long volatile* p, long v) { return __atomic_fetch_and(p, v, __ATOMIC_SEQ_CST); }
long _InterlockedOr(long volatile* p, long v) { return __atomic_fetch_or(p, v, __ATOMIC_SEQ_CST); }
long _InterlockedXor(long volatile* p, long v) { return __atomic_fetch_xor(p, v, __ATOMIC_SEQ_CST); }
long _InterlockedExchange(long volatile* p, long v) { return __atomic_exchange_n(p, v, __ATOMIC_SEQ_CST); }
long _InterlockedExchangeAdd(long volatile* p, long v) { return __atomic_fetch_add(p, v, __ATOMIC_SEQ_CST); }
long _InterlockedIncrement(long volatile* p) { return __atomic_add_fetch(p, 1, __ATOMIC_SEQ_CST); }
long _InterlockedDecrement(long volatile* p) { return __atomic_sub_fetch(p, 1, __ATOMIC_SEQ_CST); }

long _InterlockedCompareExchange(long volatile* p, long exch, long cmp)
{
    __atomic_compare_exchange_n(p, &cmp, exch, 0, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST);
    return cmp;
}

long long _InterlockedExchange64(long long volatile* p, long long v) { return __atomic_exchange_n(p, v, __ATOMIC_SEQ_CST); }
long long _InterlockedExchangeAdd64(long long volatile* p, long long v) { return __atomic_fetch_add(p, v, __ATOMIC_SEQ_CST); }
long long _InterlockedAnd64(long long volatile* p, long long v) { return __atomic_fetch_and(p, v, __ATOMIC_SEQ_CST); }
long long _InterlockedOr64(long long volatile* p, long long v) { return __atomic_fetch_or(p, v, __ATOMIC_SEQ_CST); }
long long _InterlockedIncrement64(long long volatile* p) { return __atomic_add_fetch(p, 1, __ATOMIC_SEQ_CST); }
long long _InterlockedDecrement64(long long volatile* p) { return __atomic_sub_fetch(p, 1, __ATOMIC_SEQ_CST); }

long long _InterlockedCompareExchange64(long long volatile* p, long long exch, long long cmp)
{
    __atomic_compare_exchange_n(p, &cmp, exch, 0, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST);
    return cmp;
}

void* _InterlockedExchangePointer(void* volatile* p, void* v) { return __atomic_exchange_n(p, v, __ATOMIC_SEQ_CST); }

void* _InterlockedCompareExchangePointer(void* volatile* p, void* exch, void* cmp)
{
    __atomic_compare_exchange_n(p, &cmp, exch, 0, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST);
    return cmp;
}

unsigned char _InterlockedCompareExchange128(long long volatile* dst, long long exchHigh, long long exchLow, long long* comparand)
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
