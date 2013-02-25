package Amon2::Plugin::Web::PageCache;
use 5.008_001;
use strict;
use warnings;
use Amon2::Util ();
use Cache::Memcached::Fast;
use Digest::MD5;
use Storable;

our $VERSION = '0.01';

sub init {
    my ($class, $c, $conf) = @_;

    Amon2::Util::add_method($c, '_page_cache_key', \&_page_cache_key);
    Amon2::Util::add_method($c, '_page_cache_index_key', \&_page_cache_index_key);
    Amon2::Util::add_method($c, '_cache_settings', \&_cache_settings);
    Amon2::Util::add_method($c, 'delete_page_cache', \&delete_page_cache);

    return unless $c->config->{PAGE_CACHE}->{enable};

    $c->add_trigger(
        BEFORE_DISPATCH => sub {
            my ($self) = @_;

            my $settings = $self->_cache_settings() || return;
            my $config = $self->config->{PAGE_CACHE};
            my $cache = Cache::Memcached::Fast->new($config->{memcached}),
            my $key = $self->_page_cache_key($settings);

            if(my $page = $cache->get($key)){
                my $html = $page->{body};
                my $header = $page->{header};
                return $self->create_response(
                    200,
                    [
                        'Content-Type' => $header->{content_type} || 'text/html; charset=utf-8',
                        'Content-Length' => length($html),
                    ],
                    [$html]
                );
            }
            return;
        },
        AFTER_DISPATCH => sub {
            my ($self, $res) = @_;
            return unless $res->code == 200;

            my $settings = $self->_cache_settings() || return;
            my $config = $self->config->{PAGE_CACHE};
            my $cache = Cache::Memcached::Fast->new($config->{memcached}),
            my $key = $self->_page_cache_key($settings);
            return if $cache->get($key);

            my $body = $res->body;
            my $header = { content_type => $res->header('Content-Type') || '' } ;
            $cache->set( $key, { body => $body ,header => $header }, $settings->{expire} );

            # make index for delete_page_cache
            my $index_key = $self->_page_cache_index_key({ name => ref $self, path => $self->req->path_info });
            my $index = $cache->get($index_key) || {};
            $index->{$key} = 1;
            $cache->set( $index_key, $index );
            return;
        },
    );
}

sub delete_page_cache {
    my ($self, $args) = @_;
    my $config = $self->config->{PAGE_CACHE};
    my $cache = Cache::Memcached::Fast->new($config->{memcached}),
    my $index_key = $self->_page_cache_index_key({ name => $args->{name}, path => $args->{path} });
    my $index = $cache->get($index_key) || {};
    for my $key ( keys %$index ) {
        $cache->remove( $key );
    }
    $cache->remove( $index_key );
}

sub _page_cache_key {
    my ($self, $settings) = @_;
    $settings ||= $self->_cache_settings();
    my $query_keys = $settings->{query_keys} || [];
    my $query_hash = {};
    for my $key ( @$query_keys ) {
        $query_hash->{$key} = $self->req->param($key) || '';
    }
    # https://github.com/kazeburo/Cache-Memcached-IronPlate
    my $key = join(':', 'page_cache', ref $self, $self->req->path_info, Digest::MD5::md5_hex( Storable::nfreeze($query_hash) ));
    return $key;
}

sub _page_cache_index_key {
    my ($self, $args) = @_;
    my $key = join(':', 'page_cache_index', $args->{name}, $args->{path});
    return $key;
}

sub _cache_settings {
    my ($self) = @_;

    my $appname = ref $self;
    my $path = $self->config->{PAGE_CACHE}->{path}->{$appname} || return;

    for my $key ( keys %$path ) {
        # copy from Router::Simple::Route
        my $pattern = $key;
        $pattern =~ s!
            \{((?:\{[0-9,]+\}|[^{}]+)+)\} | # /blog/{year:\d{4}}
            :([A-Za-z0-9_]+)              | # /blog/:year
            (\*)                          | # /blog/*/*
            ([^{:*]+)                       # normal string
        !
            if ($1) {
                my ($name, $pattern) = split /:/, $1, 2;
                $pattern ? "($pattern)" : "([^/]+)";
            } elsif ($2) {
                "([^/]+)";
            } elsif ($3) {
                "(.+)";
            } else {
                quotemeta($4);
            }
        !gex;

        if( $self->req->path_info =~ qr{^$pattern$} ) {
            return $path->{$key};
        }
    }
    return;
}


1;
__END__

=head1 NAME

Amon2::Plugin::Web::PageCache - Plugin for page cache

=head1 VERSION

This document describes Amon2::Plugin::Web::PageCache version 0.01.

=head1 SYNOPSIS

    package MyApp::Web;
    use Amon2::Web;

    __PACKAGE__->load_plugin('Web::PageCache');

=head1 DESCRIPTION

This plugin enables caching pages by using memcached.

=head1 CONFIGURATION

config.pl

    'PAGE_CACHE' => +{
        enable => 1,
        memcached => +{
            servers => [
                '127.0.0.1:11211'
            ],
            namespace => 'page_cache:',
        },
        path => +{
            'MyApp::Web' => +{
                '/'                         => { expire => 60 },
                '/detail'                   => { expire => 300, query_keys => [qw/p/] },
                '/member/{id:[0-9]+}'       => { expire => 60 },
                '/list'                     => { expire => 60, query_keys => [qw/p rows/] },
            },
            'MyApp::Mobile' => +{
                '/'                         => { expire => 60 },
            },
        },
    },

= item enable

To enable this plugin

    enable => 1

To disable this plugin

    enable => 0

= item memcached

Memcached settings for L<Cache::Memcached::Fast>.

= item path

Enabling cache only writing here. Set context's name, path info and cache configurations.

You can use path format like L<Router::Simple>.

If you want to recache after 60 seconds

    expire => 60

If you don't set query_keys, returns same contents.
IF you need different contents by query, set query_keys.

= head1 METHODS

= item delete_page_cache

Remove page cache.
Require context's name and path info.

    $c->delete_page_cache({ name => 'MyApp::Web', path => '/' });

= head1 SEE ALSO

L<Amon2>

=head1 AUTHOR

dameninngenn E<lt>dameninngenn.owata {at} gmail.comE<gt>

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2013, dameninngenn. All rights reserved.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
