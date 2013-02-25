package t::Util;

use File::Spec;
use File::Basename;
use lib File::Spec->rel2abs(File::Spec->catdir(dirname(__FILE__), '..', 'lib'));
use Test::TCP;

our $MEMCACHED;

sub start_memcached {
    # do we have an explicit memcached somewhere?
    if (my $servers = $ENV{TEST_MEMCACHED_SERVERS}) {
        return;
    }

    $MEMCACHED = Test::TCP->new(code => sub {
        my $port = shift;
        exec "memcached -l 127.0.0.1 -p $port";
    });

    $ENV{TEST_MEMCACHED_SERVERS} = '127.0.0.1:' . $MEMCACHED->port;
}

END { undef $MEMCACHED }


1;
