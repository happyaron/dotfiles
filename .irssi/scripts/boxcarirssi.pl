use strict;
use warnings;

#####################################################################
# This script sends notifications to your
# iPhone using your boxcar email and password when you are away.
#
# Originally I made this script for Prowl, but since people tend to
# be cheap and rather use boxcar(which is not as good) I ported it
# to boxcar. Boxcar lacks features such as priority.
#
# Commands:
# /set boxcar_email something@example.com
# /set boxcar_password password
# /set boxcar_general_hilight on/off
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
use HTTP::Request::Common;

$VERSION = "0.1";

%IRSSI = (
    authors     => "Caesar 'sniker' Ahlenhed",
    contact     => "sniker\@se.linux.org",
    name        => "boxcarirssi",
    description => "Sends notifcations when away",
    license     => "GPLv2",
    url         => "http://sniker.codebase.nu",
    changed     => "Sat Feb 12 23:56:32 CET 2011",
);

# Configuration settings and default values.
Irssi::settings_add_str("boxcarirssi", "boxcarirssi_email", "");
Irssi::settings_add_str("boxcarirssi", "boxcarirssi_password", "");
Irssi::settings_add_bool("boxcarirssi", "boxcarirssi_general_hilight", 0);

sub send_noti {
    my ($text) = @_;

    my %options = ();

    $options{'application'} ||= "Irssi";
    $options{'notification'} = $text;

    my ($userAgent, $req, $response);
    $userAgent = LWP::UserAgent->new;
    $userAgent->agent("BoxcarIrssi/1.0");
    
    $req = HTTP::Request->new(POST => "https://boxcar.io/notifications");
    $req->content("notification[from_screen_name]=" . $options{'application'} . "&notification[message]=" . $options{'notification'});
    $req->authorization_basic(Irssi::settings_get_str("boxcarirssi_email") => Irssi::settings_get_str("boxcarirssi_password"));
    
    $response = $userAgent->request($req);

    if ($response->is_success) {
        # I guess it worked, eh?
    } else {
        Irssi::print("Notification not posted: " . $response->content);
    }
}

sub pubmsg {
    my ($server, $data, $nick) = @_;

    if($server->{usermode_away} == 1 && $data =~ /$server->{nick}/i){
        send_noti("Hilighted - " . $nick . ': ' . $data);
    }
}

sub privmsg {
    my ($server, $data, $nick) = @_;
    if($server->{usermode_away} == 1){
        send_noti("PM - " . $nick . ': ' . $data);
    }
}

sub genhilight {
    my($dest, $text, $stripped) = @_;
    my $server = $dest->{server};

    if($dest->{level} & MSGLEVEL_HILIGHT) {
        if($server->{usermode_away} == 1){
            if(Irssi::settings_get_bool("boxcarirssi_general_hilight")){
                send_noti("General Hilight - " . $stripped);
            }
        }
    }
}

Irssi::signal_add_last('message public', 'pubmsg');
Irssi::signal_add_last('message private', 'privmsg');
Irssi::signal_add_last('print text', 'genhilight');
