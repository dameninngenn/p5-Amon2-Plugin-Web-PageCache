#!perl -w
use strict;
use warnings;
use utf8;

use t::Util;
use Test::More;
use Test::Requires 'Test::WWW::Mechanize::PSGI';
use Text::Xslate;
use String::Random qw(random_regex);

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
                enable => 1,
                memcached => +{
                    servers => [
                        $TEST_MEMCACHED_SERVERS,
                    ],
                    namespace => 'page_cache:',
                },
                path => +{
                    'MyApp::Web' => +{
                        '/cache/enable' => { expire => 60 },
                        '/cache/enable/expire/3sec' => { expire => 3 },
                        '/cache/enable/route/1/:id' => { expire => 60 },
                        '/cache/enable/route/2/{id:[a-zA-Z0-9]{4,18}}' => { expire => 60 },
                        '/cache/enable/route/3/*/*' => { expire => 60 },
                        '/cache/enable/query/single' => { expire => 60, query_keys => [qw/q/] },
                        '/cache/enable/query/multi' => { expire => 60, query_keys => [qw/q page rows/] },
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

    sub now { time() }

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

subtest '/cache/enable' => sub {
    $mech->get('/cache/enable');
    is $mech->status(), 200;
    my $step1 = $mech->content();

    sleep(1);

    $mech->get('/cache/enable');
    is $mech->status(), 200;
    my $step2 = $mech->content();

    is $step2, $step1;
};

subtest '/cache/disable' => sub {
    $mech->get('/cache/disable');
    is $mech->status(), 200;
    my $step1 = $mech->content();

    sleep(1);

    $mech->get('/cache/disable');
    is $mech->status(), 200;
    my $step2 = $mech->content();

    isnt $step2, $step1;
};

subtest '/cache/enable/expire/3sec' => sub {
    $mech->get('/cache/enable/expire/3sec');
    is $mech->status(), 200;
    my $step1 = $mech->content();

    sleep(1);

    $mech->get('/cache/enable/expire/3sec');
    is $mech->status(), 200;
    my $step2 = $mech->content();

    is $step2, $step1;

    sleep(2);

    $mech->get('/cache/enable/expire/3sec');
    is $mech->status(), 200;
    my $step3 = $mech->content();

    isnt $step3, $step1;
};

subtest '/cache/enable/route' => sub {
    subtest '/cache/enable/route/1/:id' => sub {
        my $id = random_regex('\w\w\w\w');
        $mech->get('/cache/enable/route/1/' . $id);
        is $mech->status(), 200;
        my $step1 = $mech->content();

        sleep(1);

        $mech->get('/cache/enable/route/1/' . $id);
        is $mech->status(), 200;
        my $step2 = $mech->content();

        is $step2, $step1;

        sleep(1);

        $mech->get('/cache/enable/route/1/' . random_regex('\w\w\w\w'));
        is $mech->status(), 200;
        my $step3 = $mech->content();

        isnt $step3, $step1;
    };

    subtest '/cache/enable/route/2/{id:[a-zA-Z0-9]{4,18}}' => sub {
        my $id = random_regex('\w\w\w\w');
        $mech->get('/cache/enable/route/2/' . $id);
        is $mech->status(), 200;
        my $step1 = $mech->content();

        sleep(1);

        $mech->get('/cache/enable/route/2/' . $id);
        is $mech->status(), 200;
        my $step2 = $mech->content();

        is $step2, $step1;

        sleep(1);

        $mech->get('/cache/enable/route/2/' . random_regex('\w\w\w\w'));
        is $mech->status(), 200;
        my $step3 = $mech->content();

        isnt $step3, $step1;
    };

    subtest '/cache/enable/route/3/*/*' => sub {
        my $path = random_regex('\w\w\w\w') . '/' . random_regex('\w\w\w\w');
        $mech->get('/cache/enable/route/3/' . $path);
        is $mech->status(), 200;
        my $step1 = $mech->content();

        sleep(1);

        $mech->get('/cache/enable/route/3/' . $path);
        is $mech->status(), 200;
        my $step2 = $mech->content();

        is $step2, $step1;

        sleep(1);

        $mech->get('/cache/enable/route/3/' . random_regex('\w\w\w\w') . '/' . random_regex('\w\w\w\w'));
        is $mech->status(), 200;
        my $step3 = $mech->content();

        isnt $step3, $step1;
    };
};

subtest '/cache/enable/query/single' => sub {
    $mech->get('/cache/enable/query/single');
    is $mech->status(), 200;
    my $step1 = $mech->content();

    sleep(1);

    $mech->get('/cache/enable/query/single?q=hoge');
    is $mech->status(), 200;
    my $step2 = $mech->content();

    isnt $step2, $step1;

    sleep(1);

    $mech->get('/cache/enable/query/single?q=こんにちは');
    is $mech->status(), 200;
    my $step3 = $mech->content();

    isnt $step3, $step1;
    isnt $step3, $step2;

    sleep(1);

    $mech->get('/cache/enable/query/single?q=');
    is $mech->status(), 200;
    my $step4 = $mech->content();

    is $step4, $step1;

    sleep(1);

    $mech->get('/cache/enable/query/single?unknown=1');
    is $mech->status(), 200;
    my $step5 = $mech->content();

    is $step5, $step1;
};

subtest '/cache/enable/query/multi' => sub {
    $mech->get('/cache/enable/query/multi');
    is $mech->status(), 200;
    my $step1 = $mech->content();

    sleep(1);

    $mech->get('/cache/enable/query/multi?q=hoge&page=1&rows=20');
    is $mech->status(), 200;
    my $step2 = $mech->content();

    isnt $step2, $step1;

    sleep(1);

    $mech->get('/cache/enable/query/multi?q=hoge&page=2&rows=20');
    is $mech->status(), 200;
    my $step3 = $mech->content();

    isnt $step3, $step1;
    isnt $step3, $step2;

    sleep(1);

    $mech->get('/cache/enable/query/multi?q=hoge&page=2&rows=20&unknown=1');
    is $mech->status(), 200;
    my $step4 = $mech->content();

    is $step4, $step3;

    sleep(1);

    $mech->get('/cache/enable/query/multi?unknown=1');
    is $mech->status(), 200;
    my $step5 = $mech->content();

    is $step5, $step1;
};

subtest 'delete page cache' => sub {
    subtest 'with no query' => sub {
        $mech->get('/cache/enable');
        is $mech->status(), 200;
        my $step1 = $mech->content();

        sleep(1);

        MyApp::Web->delete_page_cache({ name => 'MyApp::Web', path => '/cache/enable' });
        $mech->get('/cache/enable');
        is $mech->status(), 200;
        my $step2 = $mech->content();

        isnt $step2, $step1;
    };

    subtest 'with queries' => sub {
        $mech->get('/cache/enable/query/multi?q=こんにちは&page=1&rows=20');
        is $mech->status(), 200;
        my $step1 = $mech->content();

        sleep(1);

        $mech->get('/cache/enable/query/multi?q=こんにちは&page=2&rows=20');
        is $mech->status(), 200;
        my $step2 = $mech->content();

        sleep(1);

        MyApp::Web->delete_page_cache({ name => 'MyApp::Web', path => '/cache/enable/query/multi' });
        $mech->get('/cache/enable/query/multi?q=こんにちは&page=1&rows=20');
        is $mech->status(), 200;
        my $step3 = $mech->content();

        isnt $step3, $step1;

        sleep(1);

        $mech->get('/cache/enable/query/multi?q=こんにちは&page=2&rows=20');
        is $mech->status(), 200;
        my $step4 = $mech->content();

        isnt $step4, $step2;
    };
};

done_testing;
