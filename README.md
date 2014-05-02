pipeline
========

Simple utility library for working with streaming data.

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
