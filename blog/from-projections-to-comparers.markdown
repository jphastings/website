Date: 2009-11-16  
Tags: .NET, Functional Programming, Linq, Sorting  

# From Projections to Comparers

The `Enumerable` class has some useful methods to work with sequences, which are typically used to either act upon the whole object, or act upon some projection of the object if only a subset of it needs to be considered. However, all of the set-based methods such as `Distinct`, `Except` and `Union` require an `IEqualityComparer<T>` instance rather than a projection, so if you want to act on a subset of the object you can't just use a simple projection like this:

~~~ csharp
var distinct = elements.Distinct(e => e.Id); // won't compile
~~~

Instead, you have to ensure that all objects implement a specific interface or derive from a base class containing the properties you want to compare, and then write a whole new equality comparer.

~~~ csharp
public class IdentityEqualityComparer<T> : IEqualityComparer<T>
    where T : IIdentity
{
    public bool Equals(T x, T y)
    {
        return x.Id == y.Id;
    }

    public int GetHashCode(T obj)
    {
        return obj.Id.GetHashCode();
    }
}

var distinct = elements.Distinct(new IdentityEqualityComparer());
~~~

It doesn't seem very in keeping with the spirit of Linq. What we need is some way to take the projection we'd like to use in the `Distinct` method and automatically create an `IEqualityComparer<T>` from it. Fortunately, that isn't too hard to achieve by creating a comparer that uses a delegate to extract the key from an object.

~~~ csharp
public sealed class KeyEqualityComparer<T, TKey> : IEqualityComparer<T>
{
    private readonly IEqualityComparer<TKey> equalityComparer;
    private readonly Func<T, TKey> keySelector;

    public KeyEqualityComparer(Func<T, TKey> keySelector)
        : this(keySelector, EqualityComparer<TKey>.Default)
    {
    }

    public KeyEqualityComparer(Func<T, TKey> keySelector, IEqualityComparer<TKey> equalityComparer)
    {
        this.keySelector = keySelector;
        this.equalityComparer = equalityComparer;
    }

    public bool Equals(T x, T y)
    {
        return this.equalityComparer.Equals(this.keySelector(x), this.keySelector(y));
    }

    public int GetHashCode(T obj)
    {
        return this.equalityComparer.GetHashCode(this.keySelector(obj));
    }
}
~~~

This class alone improves the situation dramatically by removing the need for an interface or base class containing the common properties and allowing the projection to be written inline:

~~~ csharp
var distinct = elements.Distinct(new KeyEqualityComparer<MyType, int>(e => e.Id));
~~~

However, there is still a problem with this because we have to specify the type of the object and the type of its identity to create the comparer. This not only looks ugly, but means that the comparer cannot be used with anonymous types as there is no way of specifying their type name.

To solve this, rather than creating an instance of the comparer directly, we'll need to delegate that responsibility to factory methods which can use generic type inference. By making the factory methods extensions of `IEnumerable<T>` we can also make them easily discoverable.

~~~ csharp
public static class EnumerableExtensions
{    
    public static IEnumerable<T> Distinct<T, TKey>(
        this IEnumerable<T> source, 
        Func<T, TKey> keySelector)
    {
        var comparer = new KeyEqualityComparer<T, TKey>(keySelector);
        return source.Distinct(comparer);
    }

    public static IEnumerable<T> Distinct<T, TKey>(
        this IEnumerable<T> source, 
        Func<T, TKey> keySelector, 
        IEqualityComparer<TKey> keyEqualityComparer)
    {
        var comparer = new KeyEqualityComparer<T, TKey>(keySelector, keyEqualityComparer);
        return source.Distinct(comparer);
    }
}
~~~

With just these two classes, we can now write what we originally desired and get all elements with distinct identifiers using a projection:

~~~ csharp
var distinct = elements.Distinct(e => e.Id);
~~~

Although this entry just deals with `Distinct` you can use the same code for any other method that takes an `IEqualityComparer<T>` instead of a projection, and it's also fairly easy to adapt this approach to create an `IComparer<T>` from a projection for the `OrderBy` and `OrderByDescending` methods. It's just a shame the .NET Framework doesn't come with these overloads out of the box.