#!/usr/bin/env python3
"""Bounded compression adapters only. No SquashFS parsing or external image tools.

Python lzma supplies xz/legacy LZMA. ctypes calls system liblz4/libzstd/liblzo2.
Gzip is normally handled by Node zlib without starting this helper.
"""
import ctypes as c
import ctypes.util
import lzma
import sys
import zlib


def library(name):
    path = ctypes.util.find_library(name)
    if not path:
        raise ValueError(f"missing system library: {name}")
    return c.CDLL(path)


def function(lib, name, result, args):
    fn = getattr(lib, name)
    fn.restype, fn.argtypes = result, args
    return fn


def codec(mode, ident, data, limit):
    encode = mode == "encode"
    if ident == 1:
        if encode:
            return zlib.compress(data, 9)
        d = zlib.decompressobj()
        out = d.decompress(data, limit + 1)
        if not d.eof or d.unused_data or len(out) > limit:
            raise ValueError("invalid gzip stream or output limit")
        return out
    if ident in (2, 4):
        fmt = lzma.FORMAT_ALONE if ident == 2 else lzma.FORMAT_XZ
        if encode:
            packed = lzma.compress(data, format=fmt, check=lzma.CHECK_CRC32 if ident == 4 else -1, preset=6)
            # SquashFS legacy LZMA stores a known uncompressed length in the
            # standard .lzma header, unlike Python's streaming unknown length.
            return packed[:5] + len(data).to_bytes(8,'little') + packed[13:] if ident == 2 else packed
        d = lzma.LZMADecompressor(format=fmt, memlimit=268435456)
        out = d.decompress(data, max_length=limit + 1)
        if not d.eof or d.unused_data or len(out) > limit:
            raise ValueError("invalid lzma stream or output limit")
        return out
    source = c.create_string_buffer(data)
    if ident == 5:
        lib = library("lz4")
        if encode:
            capacity = function(lib, "LZ4_compressBound", c.c_int, [c.c_int])(len(data))
            out = c.create_string_buffer(capacity)
            n = function(lib, "LZ4_compress_default", c.c_int, [c.c_void_p,c.c_void_p,c.c_int,c.c_int])(source,out,len(data),capacity)
        else:
            out = c.create_string_buffer(limit)
            n = function(lib, "LZ4_decompress_safe", c.c_int, [c.c_void_p,c.c_void_p,c.c_int,c.c_int])(source,out,len(data),limit)
        if n <= 0:
            raise ValueError("lz4 failed")
        return out.raw[:n]
    if ident == 6:
        lib = library("zstd")
        capacity = function(lib, "ZSTD_compressBound", c.c_size_t, [c.c_size_t])(len(data)) if encode else limit
        out = c.create_string_buffer(capacity)
        if encode:
            n = function(lib, "ZSTD_compress", c.c_size_t, [c.c_void_p,c.c_size_t,c.c_void_p,c.c_size_t,c.c_int])(out,capacity,source,len(data),3)
        else:
            n = function(lib, "ZSTD_decompress", c.c_size_t, [c.c_void_p,c.c_size_t,c.c_void_p,c.c_size_t])(out,capacity,source,len(data))
        if function(lib, "ZSTD_isError", c.c_uint, [c.c_size_t])(n):
            raise ValueError("zstd failed")
        return out.raw[:n]
    if ident == 3:
        lib = library("lzo2")
        capacity = len(data) + len(data)//16 + 128 if encode else limit
        out = c.create_string_buffer(capacity)
        n = c.c_size_t(capacity)
        work = c.create_string_buffer(1048576) if encode else None
        name = "lzo1x_1_compress" if encode else "lzo1x_decompress_safe"
        rc = function(lib,name,c.c_int,[c.c_void_p,c.c_size_t,c.c_void_p,c.POINTER(c.c_size_t),c.c_void_p])(source,len(data),out,c.byref(n),work)
        if rc or n.value > capacity:
            raise ValueError("lzo failed")
        return out.raw[:n.value]
    raise ValueError("unknown compression ID")


if __name__ == "__main__":
    try:
        mode, ident, limit = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
        if mode not in ("encode", "decode") or not 0 < limit <= 2097152:
            raise ValueError("invalid codec operation or limit")
        data = sys.stdin.buffer.read(1048577)
        if not 0 < len(data) <= 1048576:
            raise ValueError("codec input limit")
        result = codec(mode, ident, data, limit)
        if len(result) > limit:
            raise ValueError("codec output limit")
        sys.stdout.buffer.write(result)
    except Exception as error:
        print(f"moonsquash codec: {error}", file=sys.stderr)
        sys.exit(1)
