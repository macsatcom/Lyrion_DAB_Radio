package Plugins::DABRadio::Plugin;

use strict;
use warnings;
use base qw(Slim::Plugin::OPMLBased);

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(string);
use JSON::XS::VersionOneAndTwo;
use LWP::UserAgent;

my $log   = Slim::Utils::Log->addLogCategory({ 'category' => 'plugin.dabradio' });
my $prefs = preferences('plugin.dabradio');

sub initPlugin {
    my $class = shift;

    $prefs->init({
        daemon_url    => 'http://your-dab-server:8080',   # <-- set in plugin settings
        icecast_host  => 'your-icecast-host',             # <-- set in plugin settings
        icecast_port  => 8000,
    });

    Plugins::DABRadio::Settings->new();

    $class->SUPER::initPlugin(
        feed   => \&handleFeed,
        tag    => 'dabradio',
        menu   => 'radios',
        is_app => 1,
        weight => 1,
    );
}

sub getDisplayName { return 'PLUGIN_DABRADIO_MODULE_NAME'; }

sub handleFeed {
    my ($client, $callback, $args) = @_;

    my $daemon_url   = $prefs->get('daemon_url')   || '';
    my $icecast_host = $prefs->get('icecast_host') || '';
    my $icecast_port = $prefs->get('icecast_port') || 8000;

    # ── Fetch MUX list from daemon ──────────────────────────────────────────
    my $muxes = _fetch_muxes($daemon_url);

    unless ($muxes && @$muxes) {
        $callback->({
            type  => 'opml',
            title => string('PLUGIN_DABRADIO_MODULE_NAME'),
            items => [{
                type  => 'text',
                name  => 'Could not reach DAB daemon at: ' . $daemon_url,
            }],
        });
        return;
    }

    # ── Build OPML tree: MUX → Services ────────────────────────────────────
    my @mux_items;

    for my $mux (@$muxes) {
        my @service_items;

        for my $svc (@{ $mux->{services} || [] }) {
            # Build stream URL using icecast host/port + mount from daemon
            my $stream_url = $svc->{stream};

            # Override host/port with locally configured values if set
            if ($icecast_host && $icecast_host ne 'your-icecast-host') {
                (my $mount = $stream_url) =~ s|^https?://[^/]+||;
                $stream_url = "http://$icecast_host:$icecast_port$mount";
            }

            push @service_items, {
                type  => 'audio',
                name  => $svc->{name},
                url   => $stream_url,
                icon  => 'plugins/DABRadio/html/images/DABRadio.png',
            };
        }

        # Add a "Switch to this MUX" action at the top of each MUX group
        unshift @service_items, {
            type => 'text',
            name => 'Freq: ' . $mux->{freq_mhz} . ' MHz  |  '
                  . scalar(@{ $mux->{services} || [] }) . ' services',
        };

        push @mux_items, {
            type  => 'outline',
            name  => $mux->{name},
            items => \@service_items,
        };
    }

    $callback->({
        type  => 'opml',
        title => string('PLUGIN_DABRADIO_MODULE_NAME'),
        items => \@mux_items,
    });
}

# ── Fetch MUX list from daemon's /muxes endpoint ───────────────────────────

sub _fetch_muxes {
    my $base = shift;
    return undef unless $base;

    eval {
        my $ua = LWP::UserAgent->new(timeout => 3);
        my $resp = $ua->get("$base/muxes");
        if ($resp->is_success) {
            return decode_json($resp->decoded_content);
        }
    };
    if ($@) {
        $log->warn("DAB daemon fetch failed: $@");
    }
    return undef;
}

1;
