=head1 NAME

Pipeline - Pipelines for map, filters processes.  
=head1 SYNOPSIS

	reduce(
		fileSource( $ARGV[0] ),
		pipeline( 
			step { decode_json $_ },
			step { $_->{name} },
			bufferedStep { my @v = sort { $a cmp $b } @$_; \@v } 50,
			filter { /^A/ },
			step { $_ =~ s/^A/E/g; $_ },
		),
		fileSink( $ARGV[1] )
	);

=head1 DESCRIPTION

Toolbox for data processing using MAP and REDUCE paradigm. Includes helper methods
for defining filters...

=over 4

=item mongoSource( $host, $dbName, $collName, $findParams )

Creates a data source using a MongoDB query cursor

=item fileSource( $filename )

Creates a data source for a file and reads it line by line.

=item step { CODE }

A step in the pipeline. 

=item bufferedStep { CODE }

A step in the pipeline. 

=item filter {CODE}

Adds a filter to the pipeline.

=item pipeline( \&step1, \&step2, ... )

Defines a data source and a set of transformations. Can be passed as
a datasource to another pipeline.

=item reduce( $src, $pipe, $acc )

Processes stream from pipeline to accumulator function. 

=back

=head2 AUTHOR

Shawn Tan, shawn@semantics3.com

=cut

package Pipeline;
use strict;
use warnings FATAL => 'uninitialized';
use lib('/usr/local/lib/perl/');
use Data::Dumper;
use JSON::XS;
use Carp ();
use Time::HiRes qw( usleep );
$SIG{__DIE__} = \&Carp::confess;
binmode STDOUT, ':utf8';
select( ( select( STDOUT ), $| = 1 )[0] );
binmode STDIN,  ':utf8';
binmode STDERR, ':utf8';

use Exporter;
our @ISA= qw( Exporter );
our @EXPORT = qw(
	mongoSource
	step
	bufferedStep
	filter
	pipeline
	reduce
	fileSource
	fileSink
);
our @EXPORT_OK = qw();

#----------------------------------------------------------------------
# fileSource( $filename )
#----------------------------------------------------------------------
#
# Creates a data source for a file and reads it line by line.
#
#----------------------------------------------------------------------
sub fileSource {
	my ( $filename ) = @_;
	my $filePointer;
	return sub {

		if ( !defined( $filePointer ) ) {
			eval {
				open( $filePointer, "< $filename" );
			};
			if ( $@ ) {
				die { end_of_stream => "Error opening '$filename'" };
			}
		}

		if( my $line = <$filePointer> ) {
			return $line;
		} else {
			print "FILE END.\n";
			close( $filePointer );
			die { end_of_stream => "End of '$filename'" };
		}
	}
}


#----------------------------------------------------------------------
# fileSink( $filename )
#----------------------------------------------------------------------
#
# Creates a data sink for a file and writes to it line by line.
#
#----------------------------------------------------------------------
sub fileSink {
	my ( $filename ) = @_;
	my $filePointer;
	return sub {
		my ( $line ) = @_;
		if ( scalar( @_ ) == 0 ) { close( $filePointer ); }
		else {
			if ( !defined( $filePointer ) ) {
				eval {
					open( $filePointer, "> $filename" );
				};
				if ( $@ ) {
					die { end_of_stream => "Error opening '$filename'" };
				}
			}
			print $filePointer $line."\n";
		}
	}
}

#----------------------------------------------------------------------
# step { CODE }
#----------------------------------------------------------------------
#
# A step in the pipeline. 
#
#----------------------------------------------------------------------
sub step (&) {
	my $code = \&{shift @_};
return sub {
	my ( $iter ) = @_;
	return sub {
		local $_ = $iter->();
		return &$code( $_ );
	};
}
}


#----------------------------------------------------------------------
# bufferedStep { CODE }
#----------------------------------------------------------------------
#
# A step in the pipeline. 
#
#----------------------------------------------------------------------
sub bufferedStep {
	my $bufferSize = shift @_;
	my $code = \&{shift @_};
my $inBuffer = [];
my $outBuffer = [];
my $ended;
return sub {
	my ( $iter ) = @_;
	return sub {
		if ( scalar( @$outBuffer ) == 0 ) {
			if ( !defined( $ended ) ) {
#					eval {
				# fill buffer
				while( scalar( @$inBuffer ) < $bufferSize ) {
					push( @$inBuffer, $iter->() );
				}
#					};
				if ( my $err = $@ ) {
					if ( ref( $err ) eq 'HASH' && ( my $info = $err->{end_of_stream} ) ) {
						$ended = $err;
					}
				}

				#transform
				local $_ = $inBuffer;
				$outBuffer = &$code( $_ );
				$inBuffer = [];

			} else {
				die $ended;
			}
		}

		# outbuffer definitely has stuff.
		my $data = shift @$outBuffer;
		return $data;
	};
}
}


#----------------------------------------------------------------------
# filter {CODE}
#----------------------------------------------------------------------
#
# Adds a filter to the pipeline.
#
#----------------------------------------------------------------------
sub filter (&) {
	my $code = \&{shift @_};
return sub {
	my ( $iter ) = @_;
	return sub {
		while( 1 ) {
			local $_ = $iter->();
			if ( &$code( $_ ) ){
				return $_ ;
			} else {
				#	print "REMOVED\n";
			}
		}
	};
}
}


#----------------------------------------------------------------------
# pipeline( \&step1, \&step2, ... )
#----------------------------------------------------------------------
#
# Defines a data source and a set of transformations. Can be passed as
# a datasource to another pipeline.
#
#----------------------------------------------------------------------
sub pipeline {
	my $steps = \@_;
return sub {
	my ( $sourceIter ) = @_;
	my $currIter = $sourceIter;
	foreach my $step ( @$steps ) { $currIter = &$step( $currIter ); }
	return $currIter;
}
}


#----------------------------------------------------------------------
# reduce( $src, $pipe, $acc )
#----------------------------------------------------------------------
#
# Processes stream from pipeline to accumulator function. 
#
#----------------------------------------------------------------------
sub reduce {
	my ( $src, $pipe, $acc ) = @_;

	my $stream = &$pipe( $src );
	eval {
		while ( 1 ) {
			my $item = $stream->();
			$acc->( $item );
		}
	};

	if ( my $err = $@ ) {
		if ( ref( $err ) eq 'HASH' && ( my $info = $err->{end_of_stream} ) ) {
		} else {
			print "STREAM ERROR: \n";
			print Dumper $err;
		}
	}
	return $acc->();
}


if (0) {
	my $sstart = Time::HiRes::gettimeofday();
	reduce(
		fileSource( $ARGV[0] ),
		pipeline(
			step { getWrapperData( $_ )->[0] },
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
				step { getWrapperData( $_ )->[0] },
				filter { $_ },
				filter { $_->{name} },
				step { encode_json( $_ ) },
			) ),
		fileSink( $ARGV[2] )
	);
	my $tend = Time::HiRes::gettimeofday();
	print "Threaded time: ".($tend - $tstart)."\n";
}

1;
