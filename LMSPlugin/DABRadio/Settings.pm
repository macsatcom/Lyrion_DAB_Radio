package Plugins::DABRadio::Settings;

use strict;
use warnings;
use base qw(Slim::Web::Settings);

use Slim::Utils::Prefs;
use Slim::Web::HTTP::CSRF;

my $prefs = preferences('plugin.dabradio');

Slim::Web::HTTP::CSRF->protectName('dabradio_settings');
Slim::Web::HTTP::CSRF->protectURI('/plugins/dabradio/settings/basic.html');

sub name   { return 'PLUGIN_DABRADIO_SETTINGS'; }
sub page   { return 'plugins/DABRadio/settings/basic.html'; }
sub prefs  { return ($prefs, qw(daemon_url icecast_host icecast_port)); }

sub handler {
    my ($class, $client, $params) = @_;

    if ($params->{saveSettings}) {
        $prefs->set('daemon_url',   $params->{daemon_url}   || '');
        $prefs->set('icecast_host', $params->{icecast_host} || '');
        $prefs->set('icecast_port', $params->{icecast_port} || 8000);
    }

    return $class->SUPER::handler($client, $params);
}

1;
