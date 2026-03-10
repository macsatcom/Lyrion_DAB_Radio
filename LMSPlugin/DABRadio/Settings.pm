package Plugins::DABRadio::Settings;

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Prefs;

my $prefs = preferences('plugin.dabradio');

sub name {
    return Slim::Web::HTTP::CSRF->protectName('PLUGIN_DABRADIO_MODULE_NAME');
}

sub page {
    return Slim::Web::HTTP::CSRF->protectURI('plugins/DABRadio/settings/basic.html');
}

sub prefs {
    return ($prefs, qw(daemon_url icecast_host icecast_port));
}

1;
