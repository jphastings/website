Date: 2013-02-28
Tags: Caching, HTTP, REST

# An incomplete and probably incorrect guide to HTTP caching

This post is an attempt to provide an easier to follow version of the rules laid out in [RFC 2616](http://tools.ietf.org/html/rfc2616) §§ 13-14 around HTTP caching and the impact of various HTTP headers on them. Some detail has been simplified and/or omitted to cover only the subset of HTTP typically used by RESTful APIs, as it was research into the blinkbox Web API that led me to write this.

Due to the nature of the content, this post is fairly long and dry. If you're not particularly interested in the details then feel free to skip to the [examples](#examples) at the end which illustrate the main caching use-cases for APIs.

I should also note up front that the HTTP caching rules are extremely complex and are spread out through the RFC, which means that it's possible - probable, even - that there are errors in this post. If you find any, please let me know and I'll update it.

## Revalidation

Revalidation is where a client or intermediate cache needs to check with the origin server whether the entity has been updated. It might seem an odd place to start, but the cacheability rules depend on it so it's easier to define first. The rules affecting revalidation are:

* The `Cache-Control: no-cache` directive doesn't prevent caching, but does require revalidation (RFC 2616 § 14.9.1).
* The `Cache-Control: max-age=0` directive requires revalidation (RFC 2616 § 14.9.4).
* The `Pragma: no-cache` directive should be treated the same as `Cache-Control: no-cache` (RFC 2616 § 14.32).

Note that the `Cache-Control: must-revalidate` directive does not require revalidation (RFC 2616 § 14.9.4)

The pseudocode implementation of these rules is:

~~~ python
def must_revalidate(response)
    if response.headers.cache_control.no_cache
        return True
    if response.headers.cache_control.max_age is 0
        return True
    if response.headers.pragma.no_cache
        return True
    return False
~~~

## Cacheability

The rules affecting cacheability for both private and shared caches are:

* Only responses to the following HTTP methods are permitted (RFC 2616 § 9):
    * `GET` - Defaults to cacheable unless prohibited by another condition
    * `HEAD` - The metadata about an entity may be used to update a previously cached entity.
    * `POST` - Defaults to non-cacheable unless explicitly allowed by a `Cache-Control` or `Expires` header.
* It is explicitly forbidden to cache responses to the following methods irrespective of any cache headers they may contain: `DELETE`, `OPTIONS`, `PUT`, `TRACE` (RFC 2616 § 9).
* It is permitted to cache responses with the following status codes: `200 OK`, `203 Non-Authoritative Information`, `206 Partial Content`, `300 Multiple Choices`, `301 Moved Permanently` and `410 Gone` (RFC 2616 § 13.4). For simplicity, client-side caches may choose to only cache `200 OK` responses.
* The `Cache-Control: no-store` directive disallows any form of caching (RFC 2616 § 14.9.2).
* If the response must be revalidated then it should have either an `ETag` or `Last-Modified` header to allow a precondition to be set for the revalidation, otherwise there's little point in caching the response.

Shared caches must also obey the following rules:

* If the `Cache-Control: private` directive is present then the response must not be cached. Note that the HTTP spec does allow this to apply to parts of messages, but it's a feature I've never seen used so am ignoring here.
* If the `Vary: *` directive is present, then the response must not be cached. This rule should, in theory, apply to private caches as well. However, because resources for a specific client which have this directive specified tend to depend on factors such as geo-location which will not change for that client, it may be reasonable for private caches to disregard this directive and cache the response anyway.
* If the `Authorization` header is present then the response may only be cached if the `Cache-Control: public` directive is present, i.e. it cannot be inferred that the response is publicly cacheable in absence of a private directive (RFC 2616 § 14.8). If you are using the `s-maxage` or `must-revalidate` directives then there are additional rules; we're not so I haven't considered them here.

Note that the `Cache-Control: no-cache` and `Pragma: no-cache` directives do not prevent caching (RFC 2616 §§ 14.9.1, 14.32).

Not all of these rules are typically applicable to clients using RESTful APIs. The pseudocode implementation of a simplified subset of rules typically useful for applications is:

~~~ python
def is_cacheable(request, response)
    if request.method is not in ["GET", "POST"]
        return False
    if response.status is not OK
        return False
    if response.headers.cache_control.no_store
        return False
    if not exists(response.body)
        return False
    if is_shared_cache
        if response.headers.cache_control.private
            return False
        if response.headers.vary.star
            return False
        if exists(request.headers.authorization) and not response.headers.cache_control.public
            return False
    if must_revalidate(response)
        if not (exists(response.headers.etag) or exists(response.headers.last_modified))
            return False
    if request.method is "GET"
        return True
    if response.headers.cache_control.public or response.headers.cache_control.private
        return True
    return response.expires > now
~~~

## Freshness and Expiration

### Response Age

The response age algorithm is taken from RFC 2616 § 13.2.3, with the simplification that it is reasonable to assume that the response delay will be negligible and can thus be discarded. This is because in interactive applications a delay of more than a few seconds is unacceptable, and typically cache lifetimes of resources will be in the order of hours. This gives the simplified rules:

* The apparent age is the difference between the current date and the `Date` header.
* If the `Age` header is present, and is greater than the apparent age, then that value is used instead.

The pseudocode implementation of these rules is:

~~~ python
def get_age(response)
    age = now - response.headers.date
    if exists(response.headers.age)
        age = max(age, response.headers.age)
    return age
~~~

### Freshness Lifetime

The freshness lifetime algorithm is taken from RFC 2616 § 13.2.4. The rules are:

* If the `Cache-Control: max-age` directive is present, then it is the freshness lifetime.
* Otherwise, if the `Expires` header is present, then the the freshness lifetime is the difference between it and the `Date` header (note that origin servers are required to send a `Date` header).
* Otherwise, if the `Last-Modified` header is present, the lifetime can be estimated as 10% of the time between the current time and the last modified time.
* Otherwise, the cache should use a default lifetime.

It is noted that caches estimating a freshness lifetime of more than 24 hours should attach Warning 113 to the response. To avoid this situation, it seems sensible to limit any estimated lifetime to no more than 24 hours.

The pseudocode implementation of these rules is:

~~~ python
def get_freshness_lifetime(response)
    if exists(response.headers.cache_control.max_age)
        return response.headers.cache_control.max_age
    if exists(response.headers.expires)
        return response.headers.expires - response.headers.date
    if exists(response.headers.last_modified)
        estimated_lifetime = (now - response.headers.last_modified) / 10
        return min(24h, estimated_lifetime)
    return 24h
~~~ 

### Expiration Date/Time

The expiration date/time of a response can be calculated by computing the time-to-live from lifetime and age, and adding to the current date. A response is considered to be expired (aka not fresh) if the current date is greater than or equal to the expiration date. This is a re-stating of the rules in RFC 2616 § 13.2.4 in terms of dates rather than ages, as checking of dates is typically easier when determining whether a response is fresh.

The pseudocode implementation is:

~~~ python
def get_expires(response)
    age = get_age(response)
    lifetime = get_freshness_lifetime(response)
    ttl = lifetime - age
    return now + ttl
~~~

### Offline Mode

Most mobile devices have an explicit offline mode where they do not attempt to connect to the internet (for example, this may be enabled on an aeroplane). When in offline mode it seems reasonable to assume that if the user is attempting to use previously cached data that the rules for history lists (RFC 2616 § 13.13) apply and that the device may display data that is stale to represent the state at the time they were connected.

## Request Preconditions

### `GET`

If a cache has a response that is stale, or requires revalidation then:

* If the cached response has a `Last-Modified` header, then the refresh request should include an `If-Modified-Since` header containing the last modified date (RFC 2616 § 13.3.4).
* If the cached response has an `ETag` header, then the refresh request should include an `If-None-Match` header containing the etag (RFC 2616 §§ 13.3.4, 14.26).

### `PUT`, `POST` and `DELETE`

When sending request to modify or delete an existing entity (i.e. a request to a URL that already exists) then, then the client should send any strong validators it has:

* The request should include an `If-Match` header, if:
    * The cached response has an `ETag` header, and
    * The etag is not weak, i.e. the etag does not have the prefix `W/` (RFC 2616 §§ 13.3.3, 13.3.4, 14.24).
* The request should include an `If-Unmodified-Since` header containing the last modified date, if:
    * The cached response has a `Last-Modified` header, and
    * The cached response has `Date` value, and
    * The `Last-Modified` value is at least 60 seconds before the `Date` value (RFC 2616 §§ 13.3.3, 13.3.4).

The pseudocode implementation of these rules is:

~~~ python
def get_if_match(request, cached_response)
    if not exists(cached_response.headers.etag)
        return None
    if cached_response.headers.etag.starts_with("W/")
        return None
    return cached_response.headers.etag
 
def get_if_unmodified_since(request, cached_response)
    if not exists(cached_response.headers.last_modified)
        return None
    if not exists(cached_response.headers.date)
        return None
    if cached_response.headers.date - cached_response.headers.last_modified < 60.0
        return None
    return cached_response.headers.last_modified
~~~

## Response Storage and Invalidation

The rules to determine whether an update is required on receiving a response are:

* If the request method is not `GET` or `HEAD` (i.e. a method that may update the server) then the cache should be updated (RFC 2616 § 13.10). Although not explicitly stated, it can be inferred that this should be done on receiving the response rather than on sending the request, because the specification mentions the `Location` response header. Similarly, although not explicitly stated, it can be reasonably assumed that the cache does not need to be updated on error responses.
    * If the response to a method that contains a `Location` and/or `Content-Location` header, then the cache should be invalidated for those locations as well, if the URI is either relative or has the same host as the request URI (RFC 2616 § 13.10).
* If a new cacheable response is received then the cache may be updated, although it is not required. For simplicity, it is reasonable to assume that we should update the cache if we receive a newer version (RFC 2616 § 13.10).
    * If the response contains a `Content-Location` header, then that is considered only a statement of the location of the content at the time of the response, and the cache cannot assume that the response can be used to fulfil a request to the URI specified in the header (RFC 2616 § 13.10).

Although not explicitly stated, it would also be reasonable to assume that the cache should be updated if a status code is received that indicates the entity does not exist.

The pseudocode implementation of these rules is:

~~~ python
def is_success(response)
    return 200 <= response.status <= 299
 
def should_invalidate_cache(request, response)
    if response.status is in [NotFound, Gone]
        return True
    if request.method is in ["GET", "HEAD"]
        return False
    return is_success(response)    
 
def process_response(request, response)
    if should_invalidate_cache(request, response)
        cache.remove(request.url)
        if exists(response.headers.location)
            cache.remove(response.headers.location)
        if exists(response.headers.content_location)
            cache.remove(response.headers.content_location)
    if is_cacheable(request, response)
        expires = get_expires(response)
        cache.put(request.url, response.body, expires)
~~~

## Origin Server Recommendations

There are some issues with the HTTP protocol that can make cache correctness more difficult on clients, and more prone to incorrect interpretation by intermediate caches. This set of recommendations should be implemented by origin servers to ensure that the documented client logic works as expected.

### Revalidation and Offline Use

To ensure correct behaviour of servers regarding revalidation and use of content in offline mode, origin servers should use the following cache control directives.

* Content that should never be cached or used offline: `Cache-Control: no-store`
* Content that may be cached, but which must be revalidated and so cannot be used offline: `Cache-Control: no-cache`
* Content that may be cached, which should be revalidated, but may be used in offline mode: `Cache-Control: max-age=0`
* Content that may be cached, which does not need to be revalidated, and may be used in offline mode: `Cache-Control: max-age=seconds`

### User-Specific Data

Private (i.e. user-specific) data is indicated in HTTP/1.1 by using the `Cache-Control: private` directive. However, HTTP/1.0 caches cannot be relied on to obey this directive. As such, for private cacheable data, origin servers should take advantage of the response age precedence rules by specifying the expiration of the data using the `Cache-Control: max-age` directive, and setting the `Expires`header to a date no later than the Date header (RFC 2616 § 14.9.3).

### `PUT` Response Ambiguity

[RFC 2616 issue 26](http://trac.tools.ietf.org/wg/httpbis/trac/ticket/22) indicates it is not clear whether the metadata in response to a `PUT` request applies to that response, or to the response that would be returned upon a subsequent `GET`. This issue would also apply to a `POST` request that returns a response body. As such, it is highly recommended origin servers ensure that either:

* They return a `200 OK` status code (typical for synchronous updates to existing entities) and ensure that the response is equivalent to that which would be retrieved by a subsequent `GET` thus rendering the ambiguity inconsequential.
* They return a `201 Created` status code (typical for creation of new entities) which means the response is not permitted to be cached.
* They return a `202 Accepted` status code (typical for asynchronous updates to existing entities) which means the response is not permitted to be cached.
* They return a `204 No Content` status code (typical for synchronous updates to existing entities) which means there is no body to be cached.

### ETags

Weak etag comparison functions are mildly confusing, and it is not permitted to send a weak etag on anything other than full-body `GET` requests (RFC 2616 § 13.3.3). The likely reason for this is that a weak etag does not imply exact equality, only semantic equivalence, and using a weak etag as a precondition would not necessarily prevent the lost edits problem. For this reason, it is highly recommended that origin servers use only strong etags.

## Examples

The following examples illustrate the five main caching use-cases that are expected to be encountered in a RESTful API. The `ETag` and `Last-Modified` headers are optional, but should be provided where possible. Note that these header sets are incomplete, and show only the headers pertaining to caching.

A response that should never be cached:

~~~
Cache-Control: no-store
Date: {now}
Expires: {now}
Pragma: no-cache
~~~

A response that may be cached, but must be revalidated before use and cannot be used stale:

~~~
Cache-Control: no-cache
Date: {now}
Expires: {now}
ETag: {etag}
Last-Modified: {modified-date}
Pragma: no-cache
~~~

A response that may be cached, which should be revalidated before use, but which may be used stale:

~~~
Cache-Control: [public|private], max-age=0
Date: {now}
Expires: {now}
ETag: {etag}
Last-Modified: {modified-date}
~~~

A response that may be cached publicly, which does not need revalidation before use (until the specified expiration):

~~~
Cache-Control: public, max-age={seconds}
Date: {now}
Expires: {now + seconds}
ETag: {etag}
Last-Modified: {modified-date}
~~~

A response that may be cached privately, which does not need revalidation before use (until the specified expiration):

~~~
Cache-Control: private, max-age={seconds}
Date: {now}
Expires: {now}
ETag: {etag}
Last-Modified: {modified-date}
~~~