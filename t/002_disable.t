#!perl -w
use strict;
use warnings;
use utf8;

use t::Util;
use Test::More;
use Test::Requires 'Test::WWW::Mechanize::PSGI';
use Text::Xslate;
use Time::HiRes;

our $TEST_MEMCACHED_SERVERS;
BEGIN {
    t::Util::start_memcached();
    $TEST_MEMCACHED_SERVERS = $ENV{TEST_MEMCACHED_SERVERS} || die "memcached server is not running";
};

{
    package MyApp;
    use parent qw/Amon2/;
    sub load_config {
        +{
            'PAGE_CACHE' => +{
                enable => 0,
                memcached => +{
                    servers => [
                        $TEST_MEMCACHED_SERVERS,
                    ],
                    namespace => 'page_cache:',
                },
                path => +{
                    'MyApp::Web' => +{
                        '/cache/enable' => { expire => 60 },
                    },
                },
            },
        };
    }

    package MyApp::Web;
    use parent -norequire, qw/MyApp/;
    use parent qw/Amon2::Web/;

    __PACKAGE__->load_plugin('Web::PageCache');

    my $xslate = Text::Xslate->new(
        syntax => 'TTerse',
        function => { 
            c => sub { Amon2->context },
        },
        path => {
            'now' => '[% c().now() %]',
        },
    );

    sub now { Time::HiRes::time }

    sub create_view { $xslate }

    sub dispatch {
        my $c = shift;
        if ($c->request->path_info =~ m!^/cache! ) {
            return $c->render('now');
        } else {
            return $c->create_response(404, [], []);
        }
    }
}

my $app = MyApp::Web->to_app;
my $mech = Test::WWW::Mechanize::PSGI->new(
    app                   => $app,
    max_redirect          => 0,
    requests_redirectable => []
);

subtest '/cache/enable on disable config' => sub {
    $mech->get('/cache/enable');
    is $mech->status(), 200;
    my $step1 = $mech->content();

    $mech->get('/cache/enable');
    is $mech->status(), 200;
    my $step2 = $mech->content();

    isnt $step2, $step1;
};

subtest '/cache/disable on disable config' => sub {
    $mech->get('/cache/disable');
    is $mech->status(), 200;
    my $step1 = $mech->content();

    $mech->get('/cache/disable');
    is $mech->status(), 200;
    my $step2 = $mech->content();

    isnt $step2, $step1;
};

done_testing;
