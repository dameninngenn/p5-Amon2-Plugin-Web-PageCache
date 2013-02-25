#!perl
use strict;
use warnings;
use Module::Build;

my $build = Module::Build->new(
    license        => 'perl',
    dynamic_config => 0,
    # dist_abstract  => 'XXX',

    build_requires     => {
        'Test::More'     => '0.98',
        'Test::Requires' => '0.06',
        'Test::WWW::Mechanize::PSGI' => 0,
        'Test::TCP' => 0,
        'String::Random' => 0,
        'File::Spec' => 0,
        'File::Basename' => 0,
    },
    configure_requires => { 'Module::Build' => '0.38' },
    requires           => {
        perl          => '5.008001',
        'Amon2' => 0,
        'Cache::Memcached::Fast' => 0,
        'Digest::MD5' => 0,
        'Storable' => 0,
    },

    no_index    => { 'directory' => [ 'inc' ] },
    name        => 'Amon2/Plugin/Web/PageCache',
    module_name => 'Amon2::Plugin::Web::PageCache',

    # script_files => [''],

    test_files           => (-d '.git' || $ENV{RELEASE_TESTING}) ? 't/ xt/' : 't/',
    recursive_test_files => 1,

    create_readme      => 1,
);
$build->create_build_script;
