/**
 * This is the latest memutils.d file PR'd to the D runtime. BE CAREFUL, it may or may not work on its own. It's uploaded
 * here so that you can stay up to date.
 */
module core.experimental.memutils;

/** memset() implementation */

/**
 * NOTE(stefanos):
 * Range-checking is not needed since the user never
 * pass an `n` (byte count) directly.
 */

/*
  If T is an array,set all `dst`'s bytes
  (whose count is the length of the array times
  the size of the array element) to `val`.
  Otherwise, set T.sizeof bytes to `val` starting from the address of `dst`.
*/

void memset(T)(ref T dst, const ubyte val)
{
    import core.internal.traits : isArray;
    const uint v = cast(uint) val;
    static if (isArray!T)
    {
        size_t n = dst.length * typeof(dst[0]).sizeof;
        Dmemset(dst.ptr, v, n);
    }
    else
    {
        Dmemset(&dst, v, T.sizeof);
    }
}

version (GNU)
{
    private void Dmemset(void *d, const uint val, size_t n)
    {
        memsetNaive(d, val, n);
    }
}
else
version (D_SIMD)
{
    /* SIMD implementation
     */
    private void Dmemset(void *d, const uint val, size_t n)
    {
        import core.simd : int4;
        version (LDC)
        {
            import ldc.simd : loadUnaligned, storeUnaligned;
        }
        else version (DigitalMars)
        {
            import core.simd : void16, loadUnaligned, storeUnaligned;
        }
        else
        {
            static assert(0, "Only DMD / LDC are supported");
        }
        // TODO(stefanos): Is there a way to make them @safe?
        // (The problem is that for LDC, they could take int* or float* pointers
        // but the cast to void16 for DMD is necessary anyway).
        void store32i_sse(void *dest, int4 reg)
        {
            version (LDC)
            {
                storeUnaligned!int4(reg, cast(int*) dest);
                storeUnaligned!int4(reg, cast(int*) (dest+0x10));
            }
            else
            {
                storeUnaligned(cast(void16*) dest, reg);
                storeUnaligned(cast(void16*) (dest+0x10), reg);
            }
        }
        void store16i_sse(void *dest, int4 reg)
        {
            version (LDC)
            {
                storeUnaligned!int4(reg, cast(int*) dest);
            }
            else
            {
                storeUnaligned(cast(void16*) dest, reg);
            }
        }
        const uint v = val * 0x01010101;            // Broadcast c to all 4 bytes
        // NOTE(stefanos): I use the naive version, which in my benchmarks was slower
        // than the previous classic switch. BUT. Using the switch had a significant
        // drop in the rest of the sizes. It's not the branch that is responsible for the drop,
        // but the fact that it's more difficult to optimize it as part of the rest of the code.
        if (n <= 16)
        {
            memsetNaive(cast(ubyte*) d, cast(ubyte) val, n);
            return;
        }
        void *temp = d + n - 0x10;                  // Used for the last 32 bytes
        // Broadcast v to all bytes.
        auto xmm0 = int4(v);
        ubyte rem = cast(ubyte) d & 15;              // Remainder from the previous 16-byte boundary.
        // Store 16 bytes, from which some will possibly overlap on a future store.
        // For example, if the `rem` is 7, we want to store 16 - 7 = 9 bytes unaligned,
        // add 16 - 7 = 9 to `d` and start storing aligned. Since 16 - `rem` can be at most
        // 16, we store 16 bytes anyway.
        store16i_sse(d, xmm0);
        d += 16 - rem;
        n -= 16 - rem;
        // Move in blocks of 32.
        // TODO(stefanos): Experiment with differnt sizes.
        if (n >= 32)
        {
            // Align to (previous) multiple of 32. That does something invisible to the code,
            // but a good optimizer will avoid a `cmp` instruction inside the loop. With a
            // multiple of 32, the end of the loop can be (if we assume that `n` is in RDX):
            // sub RDX, 32;
            // jge START_OF_THE_LOOP.
            // Without that, it has to be:
            // sub RDX, 32;
            // cmp RDX, 32;
            // jge START_OF_THE_LOOP
            // NOTE, that we align on a _previous_ multiple (for 37, we will go to 32). That means
            // we have somehow to compensate for that, which is done at the end of this function.
            n &= -32;
            do
            {
                store32i_sse(d, xmm0);
                // NOTE(stefanos): I tried avoiding this operation on `d` by combining
                // `d` and `n` in the above loop and going backwards. It was slower in my benchs.
                d += 32;
                n -= 32;
            } while (n >= 32);
        }
        // Compensate for the last (at most) 32 bytes.
        store32i_sse(temp-0x10, xmm0);
    }
}
else
{
    private void Dmemset(void *d, const uint val, size_t n)
    {
        memsetNaive(d, val, n);
    }
}

/* Naive implementation
 */
private void memsetNaive(void *dst, const uint val, size_t n)
{
    ubyte *d = cast(ubyte*) dst;
    foreach (i; 0 .. n)
    {
        d[i] = cast(ubyte)val;
    }
}


/** Core features tests.
  */
unittest
{
    ubyte[3] a;
    memset(a, 7);
    assert(a[0] == 7);
    assert(a[1] == 7);
    assert(a[2] == 7);

    real b;
    memset(b, 9);
    ubyte *p = cast(ubyte*) &b;
    foreach (i; 0 .. b.sizeof)
    {
        assert(p[i] == 9);
    }
}
