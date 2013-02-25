#!perl -w
use strict;
use Test::More tests => 1;

BEGIN {
    use_ok 'Amon2::Plugin::Web::PageCache';
}

diag "Testing Amon2::Plugin::Web::PageCache/$Amon2::Plugin::Web::PageCache::VERSION";
