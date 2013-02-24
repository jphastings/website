Date: 2009-12-20  
Tags: Algorithms, Performance, Sorting  

# Sampling very large sequences

A year or so back I posted [some methods to shuffle a sequence or take a random selection from it](/blog/shuffle-and-takerandom-extension-methods-for-ienumerable-t) using the Fisher-Yates shuffle, which work fine, but the `TakeRandom` method has problems with very large sequences (many millions of elements) because although it only shuffles the minimum number of elements needed to be returned, it always copies the entire sequence into an array which can fail if there is not sufficient contiguous virtual address space. This hasn't really been a problem as we've only been using fairly small sequences at work, but nonetheless it's been bothering me because I wanted to find a way to solve this problem even for very large sequences.

Happily, I chanced upon a description of [reservoir sampling](http://gregable.com/2007/10/reservoir-sampling.html) which gives a way to take a sample of N items from a sequence of unknown length S in O(S) time and O(N) space. I won't go into the maths as it's described well in the linked article, but as I couldn't find a readily available .NET implementation I will complement the article with one that I wrote. It's not the most beautiful code, but it works in a single pass and should be about as fast as possible.

~~~ csharp
public static IEnumerable<T> TakeRandom<T>(this IEnumerable<T> source, int count)
{
    var copied = 0;
    var reservoir = new T[count];
    var enumerator = source.GetEnumerator();
    for (; copied < count && enumerator.MoveNext(); copied++)
    {
        reservoir[copied] = enumerator.Current;
    }

    if (copied < count)
    {
        Array.Resize(ref reservoir, copied);
    }
    else
    {
        for (var upper = copied + 1; enumerator.MoveNext(); upper++)
        {
            var index = ThreadSafeRandom.Next(0, upper);
            if (index < count)
            {
                reservoir[index] = enumerator.Current;
            }
        }
    }

    ShuffleInPlace(reservoir);
    return reservoir;
}

private static void ShuffleInPlace<T>(T[] array)
{
    for (var n = 0; n < array.Length; n++)
    {
        var k = ThreadSafeRandom.Next(n, array.Length);
        var temp = array[n];
        array[n] = array[k];
        array[k] = temp;
    }
}
~~~

The one change you'll notice from the described algorithm is a call to `ShuffleInPlace` before returning the result, which performs a Fisher-Yates shuffle of the returned array. This is because although the reservoir sampling algorithm selects a random subset of a sequence, it does not return the results in a random order; this is easiest to see if you take a number of elements which is the same length as the sequence, where the result would be returned in the same order as the source sequence. As we want to use this as a drop-in replacement for the old `TakeRandom` method, we need to ensure that the result order is randomised too as callers may be depending on that behaviour.

So, now we've got rid of the O(S) copy operation, how does the performance of the new `TakeRandom` compare to the old one?

Terribly.

![TakeRandom old vs TakeRandom new](/reservoir-sampling-performance.png)

These results are the timings of taking ten random integers from sequences ranging from ten to a billion elements, timed over a thousand iterations per sequence length for shorter sequences, going down to ten iterations for longer sequences (otherwise we'd still be waiting here for the results). Both exhibit linear performance, however it is clear that for even for sequences as large as a hundred million integers the new reservoir sampling TakeRandom method is an order of magnitude slower than the old Fisher-Yates one.

It's not hard to see why this is. When N is small, both algorithms are O(S) in time, but in the old `TakeRandom` method each element simply has to be written into a contiguous block of memory which is extremely fast, whereas in the new `TakeRandom` a random number has to be generated for each element in the sequence which is comparatively slow.

However, you'll notice that the line for the old `TakeRandom` method stops at a hundred million integers, whereas the new one continues to a billion. This is because the old one fails to allocate an array of a billion integers with an `OutOfMemoryException` because on my 32-bit system there isn't enough virtual address space for a 4GB array. If there were many shuffles of large sequences happening concurrently, we might also expect shuffles of large sequences that do fit into the address space to fail randomly because of contention for address space.

As such, we can't reasonably replace the old Fisher-Yates `TakeRandom` method with the new reservoir sampling one, because for the majority case of sequences of less than a million items the performance degradation is unacceptable. Instead we can rename the new method to `Sample` and add it as an alternative method to facilitate the sampling of very large sequences, and by adding comments to it and `TakeRandom` describing the performance and memory trade-offs allow callers to choose the right method for their situation.