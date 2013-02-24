Date: 2009-09-01  
Tags: Algorithms, Performance  

# Optimised IP address to country code mapping

One of the things that web sites tend to do frequently is look up the country a user is from based on their IP address, for example to direct them to the appropriate site for their country or to restrict content that cannot be legally shown to them. There are numerous solutions to perform this mapping such as calling third-party web services or looking up the country from a database, but as it is such a commonly used function it is worthy of being optimised into an in-memory data structure.

This is potentially tricky to build as IP addresses are organised in ranges with allocated country codes (about 92000 at the current time) but there are approximately two billion possible values for the IP address itself, so to handle the mapping with reasonable memory usage we need to be able to efficiently map an individual IP address to a range without storing all of the IP addresses in the data structure.

Initial research on the net shows that a commonly used structure for IP address routing is the [Patricia trie](http://en.wikipedia.org/wiki/Radix_tree), and I also found a number of articles about it being used for [IP address to](http://www.codeproject.com/Articles/3657/Optimized-IP-to-ISO3166-Country-Code-Mapping-in-C) [country code mapping](http://www.codeproject.com/Articles/4120/Extreme-Optimization-1-1-Mapping-IP-addresses-to-c). Unfortunately the code for the all the articles I found were either released under, or appeared to be derived from code which is released under, the dreaded GPL license which means that it's too risky to even download it to take a look. The only other implementations I could find were from academia (read: incomprehensible ANSI C) which meant I'd be writing the trie myself from scratch.

Fast-forward a day and a half, and I've got a working IP address lookup table based on a Patricia trie, which supports the basic functions of adding IP address ranges and finding the range that an IP address is associated with. An optimisation I added was that instead of using one trie to hold all the nodes, I used a sparse array of 256 tries with each one corresponding to the first byte of the IPv4 address; as most of the first byte values are distinct on each bit this allows a single byte comparison rather than walking eight nodes.

The performance is pretty good. On my 2.1MHz Intel Core2 Duo machine, the trie takes around 0.8 seconds to build and can perform ten million lookups in 8.2 seconds (or around 1.2 million lookups per second).

However, there is a price to pay for this. The code is complex. It's difficult to ascertain that the code is bug-free without doing an exhaustive search of all IP addresses, and it would be difficult to come back to the code and perform any maintenance work even with the large amount of commenting. Although it was fun to investigate the structure, I'd prefer to have something simpler in our production codebase even if it does sacrifice a bit of efficiency.

Enter [binary search](http://en.wikipedia.org/wiki/Binary_search).

For any sorted list of values a binary search executes in O(lg N) time, and if it doesn't find an exact match the .NET implementation returns the bitwise complement of the next largest result. This means that if the values being searched are the start IP addresses in the range, that the index of the appropriate range can be returned by taking the value (if found) or the bitwise complement minus one (if not found) of the result for the candidate IP address. If we used a single list then we'd expect around lg 92000 = 17 comparisons per search, however if we keep the idea of using 256 lists we can bring this down to around lg (92000/256) = 9 comparisons plus one to find the correct root.

This is a much simpler data structure to build, and within about half an hour I had a working version for comparison of performance. And the results were pretty interesting.

The simple multiple sorted list structure using binary search turned out to be nearly twice as fast for lookups as the complex multiple Patricia trie one, managing around 2.1 million lookups per second. It was also faster to load, although this is slightly unfair as the data was already sorted when loaded so this result would be different if it was being loaded from unsorted data as that would affect the lists but not the tries.

Thinking about it, it isn't hard to see why this result was achieved. The nodes in the Patricia trie are necessarily implemented as classes so they can have references to each other which means that traversing the tree involves following object references around the heap, and both the building of the tree and the lookups require bit-shifting and masking operations as well as integer comparisons. By contrast the entries in the sorted lists can be structures meaning that each list is using contiguous memory, and although more comparisons are required they are simple integer ones without any bit-shifting and as such only take a single clock cycle to execute.

In terms of memory usage the binary search solution will also be better due to its entries being structures and thus having no object header, and not needing pointers to their left and right children.

Unfortunately I can't release the code for the lookup table as I wrote it during work time, but to write your own lookup table using sorted lists and binary search only takes about fifty lines and half an hour, and it will comprehensively outperform an implementation using Patricia tries which takes hundreds of lines and many hours to implement.