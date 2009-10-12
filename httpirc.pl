#!/usr/bin/perl -w
use strict;
use warnings;

use AnyEvent;
use AnyEvent::IRC::Client;
use AnyEvent::HTTPD;

use AnyEvent::Strict;

use Data::Dumper ();
use JSON qw(encode_json decode_json);

use Getopt::Long;

GetOptions(
           'irc-server=s' => \(my $opt_irc_server),
           'irc-port=i'   => \(my $opt_irc_port = 6667),
           'irc-nick=s'   => \(my $opt_irc_nick = 'http'),
           'http-port=i'  => \(my $opt_http_port = 9090),
);
die "--irc-server option required\n" unless defined $opt_irc_server;

my $c = AnyEvent->condvar;

my $con = new AnyEvent::IRC::Client;
my $httpd = AnyEvent::HTTPD->new(port => $opt_http_port);

my $quit_program = AnyEvent->condvar;

$httpd->reg_cb(
    '/' => sub {
        my ($httpd, $req) = @_;
        
        my $output = '<html><body><h1>http to irc gw</h1>'
                     .'Post to /post with channel and msg parameters to send messages.'
                     .'</body></html>';
        $req->respond({ content => [ 'text/html', $output ] });
    },
    '/post' => sub {
        my ($httpd, $req) = @_;
        warn Data::Dumper->Dump([\$req], [qw(req)]);
        my %args = $req->vars;
        my $msg     = $args{msg};
        my $channel = $args{channel};
        my @channels = ref $channel ? @$channel : ($channel);
        @channels = map { m/^#/ ? $_ : '#' . $_ } @channels;

        for my $channel (@channels) {
            $con->send_srv("JOIN", $channel);
            $con->send_chan($channel, 'PRIVMSG', $channel, $msg);
        }

        my $response = {channels => \@channels, msg => $msg};
        $req->respond({content => ['text/json', encode_json($response)]});
    }
);

$con->reg_cb(
    connect => sub {
        my ($con, $err) = @_;
        if (defined $err) {
            warn "connect error: $err\n";
            return;
        }
    }
);
$con->reg_cb(registered => sub { print "I'm in!\n"; });
$con->reg_cb(disconnect => sub { print "I'm out!\n"; $c->send });
$con->reg_cb(
    sent => sub {
        my ($con) = @_;

        if ($_[2] eq 'PRIVMSG') {
            print "Sent message!\n";
        }
    }
);

#$con->send_srv(
#    PRIVMSG => 'ask_',
#    "Hello there I'm the cool AnyEvent::IRC test script!"
#);

#$con->send_srv("JOIN", "#test");
#$con->send_chan("#test", "PRIVMSG", "#test", "hi, i'm a bot!");

$con->connect($opt_irc_server, $opt_irc_port, {nick => $opt_irc_nick});

$quit_program->recv;

$con->disconnect;


1;
