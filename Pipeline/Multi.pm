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

use forks;
use forks::shared;
#use threads;
#use threads::shared;

use Thread::Queue;
use Thread::Semaphore;

sub reloadModules {
	while ( my ($module, $path) = each %INC ) {
		if ( $module =~ 'Semantics3' ) {
			no warnings 'redefine';
			#	require ( delete $INC{  $module } );
		}
	}
}


sub multi {
	my ( $threadPoolSize, $step ) = @_;
	return sub {
		my ( $srcIter ) = @_;
		my $inBuffer;
		my $outBuffer;
		my @threads = qw( );
		my $sem;
		my $ended;
		return sub {
			if ( !defined( $inBuffer ) ) {
				$inBuffer  = Thread::Queue->new;
				$outBuffer = Thread::Queue->new;
				$sem       = Thread::Semaphore->new(0);
				for my $i ( 1..$threadPoolSize ) {
					my $thr = threads->create( sub {
							my $id = $i;
							print "[Thread $id] Reloading modules...";
							reloadModules;
							print "Done.\n";
							my $waiting = 0;
							my $kill = 0;
							$SIG{'KILL'} = sub {
								$kill = 1;
								if ( $waiting && $inBuffer->pending == 0 ) {
									print "[Thread $id] BEING KILLED!\n";
									threads->exit();
								}
							};
							my $iter = &$step( sub {
									print "[Thread $id] Waiting for inBuffer.\n";
									if ( $inBuffer->pending == 0 ) { $sem->up; }
									$waiting = 1;
									my $item = $inBuffer->dequeue;
									$waiting = 0;
									print "[Thread $id] Got item from inBuffer.\n";
									return $item;
								} );
							print "[Thread $id] Initialised.\n";
							while ( !$kill || $inBuffer->pending > 0 ) {
								my $item = $iter->();
								print "[Thread $id] Done processing item.\n";
								$outBuffer->enqueue( $item );
								$sem->up;
								print "[Thread $id] Put item in outBuffer\n";
								#print "[Thread $id] ".Dumper( $outBuffer );
							}
						} );
					push( @threads, $thr );
				}
			}
			if ( !defined( $ended ) ) {
				eval {
					print "[MAIN] Getting next.\n";
					do {
						print "[MAIN] Waiting for output\n";
						while ( $outBuffer->pending + $inBuffer->pending < $threadPoolSize ) {
							print "[MAIN] Put new item in inBuffer\n";
							my $item = $srcIter->();
							$inBuffer->enqueue( $item );
						}
						$sem->down;
					} while ( $outBuffer->pending == 0 );
				};
				if ( my $err = $@ ) {
					if ( ref( $err ) eq 'HASH' && ( my $info = $err->{end_of_stream} ) ) {
						$ended = $err;
					}
				}
			} else {
				if ( $outBuffer->pending == 0 ) {
					print "Killing threads.\n";
					for ( @threads ) { $_->kill('KILL')->detach(); }
					die $ended;
				}
			}
			my $out = $outBuffer->dequeue;
			return $out;
		}
	}
}
