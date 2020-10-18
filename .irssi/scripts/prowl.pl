use strict;
use warnings;

#####################################################################
# This script sends notifications to your
# iPhone using the prowl API when you are away.
#
# This script is loosely based on Denis Lemire's
# script, you can find his page on: http://www.denis.lemire.name/
#
# This script have some major differences in both code and usage
# from his script. The configuration he uses *won't* work with
# this script.
#
# Commands:
# /set prowl_api_key API_KEY
# /set prowl_general_hilight on/off
# /set prowl_priority_channel -2 up to 2
# /set prowl_priority_pm -2 up to 2
# /set prowl_priority_general -2 up to 2
# /set prowl_ignore_nettag NETWORKS # Networks in this case is a
#                                     comma separated list of
#                                     network tags that should
#                                     be ignored.
#
# "General hilight" basically referrs to ALL the hilights you have
# added manually in irssi, if many, it can get really bloated if
# turned on. Default is Off.
#
# You will need the following packages:
# LWP::UserAgent (You can install this using cpan -i LWP::UserAgent)
# Crypt::SSLeay  (You can install this using cpan -i Crypt::SSLeay)
# 
# Or if you're using Debian GNU/Linux:
# apt-get update;apt-get install libwww-perl libcrypt-ssleay-perl
#
#
# eth0 will prevail. || irc.eth0.info
#
#####################################################################


use Irssi;
use Irssi::Irc;
use vars qw($VERSION %IRSSI);

use LWP::UserAgent;

$VERSION = "0.5";

%IRSSI = (
    authors     => "Caesar 'sniker' Ahlenhed",
    contact     => "sniker\@codebase.nu",
    name        => "prowl",
    description => "Sends prowlnotifcations when away",
    license     => "GPLv2",
    url         => "http://sniker.codebase.nu",
    changed     => "Mon Jun 23 17:14:23 CEST 2014",
);

# Configuration settings and default values.
Irssi::settings_add_str("prowl", "prowl_api_key", "");
Irssi::settings_add_bool("prowl", "prowl_general_hilight", 0);
Irssi::settings_add_str("prowl", "prowl_priority_channel", 0);
Irssi::settings_add_str("prowl", "prowl_priority_pm", 0);
Irssi::settings_add_str("prowl", "prowl_priority_general", 0);
Irssi::settings_add_str("prowl", "prowl_ignore_nettag", "");

# The whole "send_noti" function is pretty much taken from the prowl example script.
sub send_noti {
    my ($event, $text, $priority) = @_;

    my %options = ();

    $options{'application'} ||= "Irssi";
    $options{'event'} = $event;
    $options{'notification'} = $text;
    $options{'priority'} = $priority;
    

    # This check isn't really needed, just added if someone would
    # would define $options{'apikey'} manually in the script.
    if(!exists($options{'apikey'})){
        $options{'apikey'} = Irssi::settings_get_str("prowl_api_key");
        chomp $options{'apikey'};
    }else{
        Irssi::print("There is some kind of trouble with the API key.");
    }

    $options{'application'} =~ s/([^A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg;
    $options{'event'} =~ s/([^A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg;
    $options{'notification'} =~ s/([^A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg;

    my ($userAgent, $request, $response, $requestURL);
    $userAgent = LWP::UserAgent->new;
    $userAgent->agent("ProwlScript/0.5");

    $requestURL = sprintf("https://api.prowlapp.com/publicapi/add?apikey=%s&application=%s&event=%s&description=%s&priority=%d",
        $options{'apikey'},
        $options{'application'},
        $options{'event'},
        $options{'notification'},
        $options{'priority'});

    $request = HTTP::Request->new(GET => $requestURL);
    $response = $userAgent->request($request);

    if ($response->is_success) {
        # I guess it worked, eh?
    } elsif ($response->code == 401) {
        Irssi::print( "Notification not posted: incorrect API key.");
    } else {
        Irssi::print("Notification not posted: " . $response->content);
    }
}

sub pubmsg {
    my ($server, $data, $nick, $nick_addr, $target) = @_;
    if(!Irssi::settings_get_bool("prowl_general_hilight")){
        if($server->{usermode_away} == 1 && $data =~ /$server->{nick}/i && index(Irssi::settings_get_str("prowl_ignore_nettag"), $server->{tag}) == -1){
            send_noti("Hilighted " . $server->{tag} . "/" . $target, $nick . ': ' . $data, Irssi::settings_get_str("prowl_priority_channel"));
        }
    }
}

sub privmsg {
    my ($server, $data, $nick) = @_;
    if($server->{usermode_away} == 1 && index(Irssi::settings_get_str("prowl_ignore_nettag"), $server->{tag}) == -1){
        send_noti("PM @ " . $server->{tag}, $nick . ': ' . $data, Irssi::settings_get_str("prowl_priority_pm"));
    }
}

sub genhilight {
    my($dest, $text, $stripped) = @_;
    my $server = $dest->{server};

    if($dest->{level} & MSGLEVEL_HILIGHT) {
        if($server->{usermode_away} == 1 && index(Irssi::settings_get_str("prowl_ignore_nettag"), $server->{tag}) == -1){
            if(Irssi::settings_get_bool("prowl_general_hilight")){
                send_noti("General Hilight " . $server->{tag} . "/" . $dest->{target}, $stripped, Irssi::settings_get_str("prowl_priority_general"));             
            }
        }
    }
}

Irssi::signal_add_last('message public', 'pubmsg');
Irssi::signal_add_last('message private', 'privmsg');
Irssi::signal_add_last('print text', 'genhilight');
