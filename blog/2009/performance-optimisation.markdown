Date: 2009-11-20  
Tags: Performance, Testing  

# Performance optimisation

No blog entry about performance optimisation would be complete without citing [Michael A. Jackson's](http://en.wikipedia.org/wiki/Michael_A._Jackson) rules, so let's get it over with now:

 1. Don't do it.
 2. (For experts only!) Don't do it yet.

There's a reason that these lines are so often cited, and it's to try and stop the hordes of people keen to micro-optimise their code from doing so. If you try and improve performance by optimising small sections of an application using your own guesswork as to where and how, then the only likely outcome is that you'll make no difference at all to the overall performance of the application, while making the code less maintainable.

If you really want to make a difference to the performance of your application, you need to follow a rigorous and structured approach. It starts with requirements. Before you do anything to optimise your application you need to work out what the performance requirements are so that you know whether you're currently meeting them, how much you have to do to meet them, and when you can stop optimising because the application is fast enough.

Requirements should be specific and quantitative. A good performance requirement might look something like this:

> When running on hardware representative of the production environment, the website must be able to handle at least 300 concurrent users with think times centred around the mean using normal distribution. Each request must have a time to last byte of no more than two seconds. The users will be carrying out the following mix of key scenarios: 65% browsing products, 15% searching for products, 10% purchasing products, 5% registering and 5% writing product reviews.

Let's break this requirement down.

Firstly, we've stated the hardware the tests are run on must be representative of the production hardware. This is important because there are four main factors that cause performance bottlenecks (processor, memory, disks and network) and which of these causes the bottleneck may depend on the hardware the application runs on – for example if you have slow disks on your test environment then you may believe that the bottleneck is with disk IO, but if you have fast disks on the production environment then it may not actually be an issue. Note that the requirement says "representative of" rather than "the same as" because you can miss out things required for redundancy in the production environment such as clusters without affecting the performance characteristics.

Secondly we've stated the performance goal of 300 concurrent users, and included our definition of a user. The definition of a user is important because 300 concurrent users with think time is very different to 300 concurrent users submitting requests as fast as possible. I prefer to include think times in the tests because it's easier to compare the results to real user capacity, but this may not be feasible if you're trying to get a very high load.

Thirdly we've stated the restrictions on the goal, that all qualifying requests must complete in two seconds or less. This is a fairly typical requirement for web applications, although generally up to four seconds is considered acceptable. You might also want to include the type of network that the users will be emulating to take into account the bandwidth and latency, but that's less important than it used to be now that the vast majority of people use fast broadband connections.

Finally we've stated the how the distribution of load will be created. It's important to try and make this load representative of the real usage patterns of your application; collecting statistics from your analytics engine can help with this. Although it isn't stated in the requirement, you should also ensure that the load tests are using a reasonable range of the catalogue, because browsing or searching for the same item repeatedly will give unrepresentative cache hit ratios.

Once you have your requirements defined and load tests written, you can enter the optimisation cycle:

 1. Measure the actual performance of your application.
 2. If the actual performance meets the required performance, stop optimising.
 3. Profile the application and find the bottleneck.
 4. Try to fix the bottleneck.
 5. Go to 1.

Start off with a fairly low load and let it run for a minute or so to let the system warm up, then gradually ramp up the load every few minutes. When the load won't go any higher and/or the request time gets too high, stop the test.

Most applications will find that the performance is sufficient, so this is as much as you need to do. Modern hardware is so fast that even a couple of modest web servers and a database server are likely to be enough to meet the requirements for most applications, unless you've set your requirements unrealistically high or written the application particularly badly.  

If you don't meet the performance requirements, then the fun begins.

The first port of call for working out what's slowing the application down isn't a profiler, it's the system performance counters. Before you can begin profiling you need to know what to profile, and at the moment you don't know whether it's the web servers, application servers or the database server causing the problem. A good guide to the performance counters you should be monitoring, and what to look for, [can be found at TechNet](http://technet.microsoft.com/en-us/library/cc976785.aspx).

Set up your performance counters in perfmon and repeat the test process, this time noting down the performance counter figures for each load level once the value reaches a fairly steady state. When the test is finished, plot the figures for each counter on a graph. You should notice that one of the counters gives a point of inflexion at the high load level, and that's the culprit causing the bottleneck (this doesn't always happen, and at that point you have to start using your intuition a bit, but it's a pretty good rule of thumb).

Now you know which server the bottleneck is on, and which system resource is causing it, you can start optimising. This doesn't necessarily mean optimising the code; it might be an infrastructure issue. For example if you don't have much memory in the web server and its memory counters are indicating that memory is an issue, it's probably quicker and easier to just stick some more memory in the box than to do any code optimisation. Similarly if your database server is indicating that disk IO is a problem, and you have slow disks or all databases are on one spindle, then it might be a better approach to put faster disks in place or move different databases and/or the log/data files onto different spindles.

If you can't solve the problem by throwing hardware at it, then you're actually going to have to optimise your code.

Start up your favourite profiler and ramp the load up until you see issues with user load or request time. You will most likely not reach numbers as high as in the un-profiled run because the additional diagnostics from the profiler will slow down the code being profiled. You should be rewarded with output of the slowest queries in the database server, or the most expensive methods (time and processor) for application code.

Attempt to fix only the main bottleneck at this point. It's tempting to start fixing other smaller issues flagged by the profiler as well but that's a waste of time because these are likely to change when you fix the main bottleneck, and you don't know if you actually need to fix them to make the application fast enough to meet your goals. While attempting the fix, try to use specific load tests and the profiler to target the component, so that you can get short-cycle feedback as to whether you're actually improving it and by how much. When you're happy with the fix, go back to step 1 and repeat the whole cycle again until you're done.

There's an [urban legend](http://www.snopes.com/business/genius/where.asp) that's been doing the rounds for years:

> Nikola Tesla visited Henry Ford at his factory, which was having some kind of difficulty. Ford asked Tesla if he could help identify the problem area. Tesla walked up to a wall of boilerplate and made a small X in chalk on one of the plates. Ford was thrilled, and told him to send an invoice.
> 
> The bill arrived, for $10,000. Ford asked for a breakdown. Tesla sent another invoice, indicating a $1 charge for marking the wall with an X, and $9,999 for knowing where to put it.

You could equally well apply this legend to a performance tester helping to optimise an underperforming system. The important skill isn't being able to optimise code; it's being able to identify what the bottlenecks are, whether they're hardware or code related, and which specific pieces of hardware or code need improving. If you ignore the process and just start optimising code you think might be slow, you're doing no more than sticking a whole bunch of $1 Xs everywhere in the hope you hit the right spot.