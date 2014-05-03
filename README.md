Pipeline.pm
========

Simple utility library for working with streaming data.

Under this framework, data comes from a data `source` and flows through
a bunch of transformations and filters until it comes to a `sink`. The 
way these transformation steps are written are similar to how perl takes 
an input for its `map` functon.


### Pipeline

####`step {CODE}`

Implement a transformation step to be taken on the input `$_`. 

####`filter {CONDITION}`

Filter out only items in the stream that satisfies CONDITION. 

####`bufferedStep {CODE} $bufferSize`

Operates on data in bulk, filling up the buffer and making the bulk call every `$bufferSize`.
Useful for bulk ID lookups in a table.

####Example

A simple example to fetch some page data and perform some 
transformation on it before storing it in another file.

```perl
my $sstart = Time::HiRes::gettimeofday();
reduce(
	fileSource( $ARGV[0] ),
	pipeline(
		step { scrapePage( $_ ) },
		filter { $_ },
		filter { $_->{name} },
		step { encode_json( $_ ) },
	),
	fileSink( $ARGV[1] )
);
my $send = Time::HiRes::gettimeofday();
print "Single Threaded time: ".($send - $sstart)."\n";
```

### Pipeline::Multi (Experimental!)

Multi-processing using this library is still experimental.

You can block off series of steps to be performed in parallel, and then specify
the number of processes that will be forked to execute them.

```perl
my $tstart = Time::HiRes::gettimeofday();
reduce(
	fileSource( $ARGV[0] ),
	multi( 4, pipeline(
			step { scrapePage( $_ ) },
			filter { $_ },
			filter { $_->{name} },
			step { encode_json( $_ ) },
		) ),
	fileSink( $ARGV[2] )
);
my $tend = Time::HiRes::gettimeofday();
print "Threaded time: ".($tend - $tstart)."\n";
```
