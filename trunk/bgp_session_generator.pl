#!/usr/bin/perl
#
# $Id$
#
# Elisa Jasinska <elisa.jasinska@ams-ix.net>
#
# Copyright (c) 2009 AMS-IX B.V.
#
# This package is free software and is provided "as is" without express 
# or implied warranty.  It may be used, redistributed and/or modified 
# under the terms of the Perl Artistic License (see
# http://www.perl.com/perl/misc/Artistic.html)
#

use strict;
use warnings;

use Getopt::Std;
use Net::BGP::Process;
use Net::BGP::Peer;
use Net::IP;
use Data::Dumper;


# initialize options and handle help message
my %opt = ();
$Getopt::Std::STANDARD_HELP_VERSION = 1;
getopts("hi:a:s:f:u:c:rwxt:vo:", \%opt)
  or &HELP_MESSAGE(\*STDOUT);
&HELP_MESSAGE(\*STDOUT) if $opt{h};
&VERSION_MESSAGE(\*STDOUT) if $opt{v};


# call input validation
&input_validation(\%opt);


# generate list of peer IPs and ASs
&message(\*STDOUT,'generating list of peers...');
my $peers_array_ref = 
  &generate_peers(
    $opt{s},
    $opt{f}
  );


# generate list of prefixes for the peers (if option -u set)
&message(\*STDOUT,'generating list of prefixes...') if $opt{u};
my $prefixes_hash_ref = 
  &generate_prefixes(
    $peers_array_ref,
    $opt{u}
  ) if $opt{u};
  

# generate Net::BGP::Peer objects from peer list
&message(\*STDOUT,'generating peer objects...');
my $sessions_array_ref = 
  &generate_sessions(
    $opt{i},
    $opt{a},
    $peers_array_ref
  );


# generate update objects
&message(\*STDOUT,'generating update objects...'); 
&message(\*STDOUT,'... this might take a while, be patient...');
my $updates_hash_ref = 
  &generate_updates(
    $sessions_array_ref,
    $opt{c},
    $prefixes_hash_ref,
  );


# initialize Net::BGP::Process 
my $bgp  = Net::BGP::Process->new();


# add sessions to BGP process
&message(\*STDOUT,'adding sessions...') if $opt{u};
&add_sessions($bgp,$sessions_array_ref);


# parse instructions and add timers to sessions
&message(\*STDOUT,'adding updates and timers...') if $opt{u};
&parse_instruction_order_and_add_timers(
  $sessions_array_ref,
  $updates_hash_ref,
  $opt{t},
  $opt{o},
  $opt{w},
);


# start BGP loop
&message(\*STDOUT,'entering event loop... ready for take-off!');

eval {
  $bgp->event_loop();
};

if ($@ =~ /bind/) {
  die "ERROR: something went wrong. maybe you are not root? or something is busy on port 179?\n";
} else {
  die "$@";
}


#########################################################################
# version message
#########################################################################
# ipput:
#  - file handle to STDOUT
#########################################################################
sub VERSION_MESSAGE { 
#########################################################################

  my $fh = shift; 

  print $fh "version 1.2\n";

}


#########################################################################
# help message
#########################################################################
# ipput:
#  - file handle to STDOUT
#########################################################################
sub HELP_MESSAGE {
#########################################################################

  my $fh = shift; 

  print $fh
    qq{usage: bgp_session_generator.pl [OPTIONS]

    -h                     : this (help) message
    -v                     : print version

    -i <IP>                : the router's IP
    -a <AS>                : the router's AS

    -s <range of IP addr>  : range of IP addresses for peering sessions 
                             to the router (e.g. '10.23.0.1 - 10.23.0.101').
                             those addresses need to be specified on the 
                             hosts interface (e.g. interface aliases) 
    -f <AS of first pfx>   : AS of the lowest numbered peering session 
                             (all following will be each decreased by 1)

    -u <# of pfxs>         : generates unique prefixes per peering session
                             argument: number prefixes to be generated
                             (cannot be used together with -c option)

    -c <list of pfxs>      : cookie-cutter, comma-separated list of 
                             prefixes which will be used for each peering 
                             session (e.g. '10.11.12.0/24, 10.12.13.0/24', 
                             cannot be used together with -u)

    -t <sec>               : time between session establishment and each 
                             update

    -w                     : withdraw the prefixes, default announces
                             (only if -o is not used)

    -o                     : sequence of order and number of prefixes to 
                             announce/withdraw (e.g. '2a,2w,4a,3w,15a,16w' 
                             - this would announce 2, withdraw those 2 
                             again, announce 4, withdraw the last 3 of 
                             those... etc.). pick your order carefully, 
                             not more announces than defined prefixes (via 
                             -u or -c) are allowed and not more withdraws 
                             than prefixes so far announced are possible\n};
  exit;

}


#########################################################################
# print message wrapper
#########################################################################
# ipput:
#  - file handle to output
#  - message string
#########################################################################
sub message { 
#########################################################################

  my $fh = shift; 
  my $message = shift;

  my $localtime = localtime();

  print $fh "$localtime - $message\n";

}


#########################################################################
# input validation
#########################################################################
# ipput:
#  - hash reference to options received from getopt
#  - opt values that include IP addresses or prefixes are transformed
#    into Net::IP objects at this point
#########################################################################
sub input_validation {
#########################################################################

  my $opt = shift;

  ### router's IP
  defined $opt->{i} or 
    die "ERROR: router's IP missing (-i)\n";
  $opt->{i} = new Net::IP("$opt->{i}") or 
    # IP will be rewritten into a Net::IP object
    die "ERROR: router's IP address doesn't seem valid\n";

  ### router's AS
  defined $opt->{a} or 
    die "ERROR: router's AS missing (-a)\n";
  $opt->{a} =~ /^\d+$/ or 
    die "ERROR: router's AS (-a) is not an integer\n";
  $opt->{a} > 0 or 
    die "ERROR: router's AS (-a) is negative, that is not valid\n";

  ### peering session IP range
  defined $opt->{s} or 
    die "ERROR: range of IP addresses for peering sessions missing (-s)\n";
  # trim whitespaces
  $opt->{s} =~ s/\s//g; 
  $opt->{s} = new Net::IP("$opt->{s}") or 
    # IP will be rewritten into a Net::IP object
    die "ERROR: range of IP addresses for peering sessions (-s) doesn't seem valid\n";

  ### first peering sessions AS numer 
  defined $opt->{f} or 
    die "ERROR: AS of lowerst numbered peering session missing (-f)\n";
  $opt->{f} =~ /^\d+$/ or 
    die "ERROR: lowest numbered peering session AS (-f) is not an integer\n";
  $opt->{f} > 0 or 
    die "ERROR: lowest numbered peering session AS (-f) is negative, that is not valid\n";

  ### time interval
  defined $opt->{t} or 
    die "ERROR: time interval missing (-t)\n";
  $opt->{t} =~ /^\d+$/ or 
    die "ERROR: time interval (-t) is not an integer\n";
  $opt->{t} > 0 or 
    die "ERROR: time interval (-t) is negative, that is not valid\n";

  ### number of unique prefixes to be generated
  if (defined $opt->{u}) {
    # check if excluding options are used toegther
    die "ERROR: -u cannot be used together with -c\n" 
      if defined $opt->{c};
    $opt->{u} =~ /^\d+$/ or 
      die "ERROR: number of unique prefixes sent by each session is not an integer (-u)\n";
    $opt->{u} > 0 or 
      die "ERROR: number of unique prefixes (-u) is negative, that is not valid\n";
    $opt->{u} <= 255 or 
      die "ERROR: number of unique prefixes (-u) cannot be greater than 255, $opt->{u} is too much\n";
  } 

  ### cookie-cutter prefix list
  if (defined $opt->{c}) {
    # check if excluding options are used toegther
    die "ERROR: -c cannot be used together with -u\n" 
      if defined $opt->{u};
    # trim whitespaces
    $opt->{c} =~ s/\s//g; 
    # split prefixes and put them into an array
    my @prefixes = split(/,/, $opt->{c});
    # check each prefix for validity
    foreach my $prefix (@prefixes) {
      my $test_prefix = new Net::IP("$prefix") or 
        die "ERROR: cookie-cutter prefixes do not seem valid (-c)\n";
    } 
    # assign array reference 
    $opt{c} = \@prefixes;
  }

  die "ERROR: either -u or -c option must be specified\n" 
    unless defined $opt->{u} or defined $opt->{c};

  ### order and number of prefixes to announce/withdraw
  if (defined $opt->{o}) {

    # remove whitespaces and put instructions into an array
    $opt->{o} =~ s/\s//g; 
    my @order = split(/,/, $opt->{o});

    # check details 
    #  - are instruction valid
    #  - are announces/withdraws given in right order and with the correct amount
    #  - is max update count from order instructions bigger than the prefixes received/generated 

    # number of prefixes defined in either -u or -c
    my $nr_of_prefixes = 0;
    $nr_of_prefixes = $opt{u} if defined $opt{u};
    $nr_of_prefixes = scalar @{$opt{c}} if defined $opt{c};
    my $announces = 0;
    my $withdraws = 0;
    my $current_prfxs = 0;
    foreach my $instruction (@order) {
      die "ERROR: order instruction string seems not to be valid (-o)" 
        unless $instruction =~ /(\d+)([aw]{1})/;
      $current_prfxs = $current_prfxs + $1 if $2 eq 'a';
      $current_prfxs = $current_prfxs - $1 if $2 eq 'w';
      $announces = $announces + $1 if $2 eq 'a'; 
      $withdraws = $withdraws + $1 if $2 eq 'w'; 
      die "ERROR: order instruction string - too many withdraws for too few announces, " .
          "re-think your instructions! (-o)\n" if $withdraws > $announces;
      die "ERROR: order instruction string - number of updates in order instruction must be " . 
          "smaller or equal to the generated prefixes in -u or the number of given prefixes in -c, " . 
          "$current_prfxs is too big (-o)\n" if $current_prfxs > $nr_of_prefixes;
    }
  
    # assign array reference 
    $opt{o} = \@order;
  }

}


#########################################################################
# generate peers
#########################################################################
# input:
#  - peering sessions IP range // Net::IP object $opt{s}
#  - first AS to use for peering sessions // $opt{f}
# output:
#  - array reference with each element being an array
#    with the first element the peer's IP and the second the peer's AS
#########################################################################
sub generate_peers {
#########################################################################

  my $peering_sessions_ip_range = shift;
  my $first_as_number = shift;

  my @peers = ();

  # split up octets from first and last IP in an array
  my @first = split(/\./, $peering_sessions_ip_range->ip());
  my @last = split(/\./, $peering_sessions_ip_range->last_ip());

  if ($first[2] == $last[2]) {

    my $third_octet = $first[2];

    # just iterate over the fourth octets
    foreach ($first[3] .. $last[3]) {

      my $fourth_octet = $_;

      push(@peers,["$first[0].$first[1].$third_octet.$fourth_octet",$first_as_number]);

      $first_as_number--;

    }

  }


  # if the given range is bigger than one /24
  # (third octests from first and last address are different)
  elsif ($first[2] < $last[2]) {

    # we will have 3 parts we need to iterate over:
    # 1) the first part, from the first given 4th octet .. 255
    # 2) possibly a number of complete /24's to iterate over, from 0 .. 255
    # 3) the last part, from 0 .. until the last given 4th octet

    # iterate over the fourth octet, for the first part
    # with the third octet being the first one given
    my $third_octet = $first[2];

    foreach ($first[3] .. 255) {

      my $fourth_octet = $_;

      push(@peers,["$first[0].$first[1].$third_octet.$fourth_octet",$first_as_number]);

      $first_as_number--;

    }


    # only if there is more than a range of /23, we need the second part
    unless ($first[2]+1 == $last[2]) {

      # we need to figure out the number of complete /24's in between
      # to iterate over them completely
      my $different_third_octets = $last[2] - $first[2] - 1;

      # iterate the given number of times over the entire /24s
      foreach (1 .. $different_third_octets) {

        # the third octet will increase by one each time
        $third_octet++;

        # iterate over the fourth octet for the entire /24
        foreach (0 .. 255) {

          my $fourth_octet = $_;

          push(@peers,["$first[0].$first[1].$third_octet.$fourth_octet",$first_as_number]);

          $first_as_number--;

        }

      }

    }


    # iterate over the fourth octet, for the last part
    # with the third octet being the last one given
    $third_octet = $last[2];

    foreach (0 .. $last[3]) {

      my $fourth_octet = $_;

      push(@peers,["$first[0].$first[1].$third_octet.$fourth_octet",$first_as_number]);

      $first_as_number--;

    }

  }

  else {

    # if we are in here, that's bad - the third octet of the first IP should never be 
    # bigger than the third octet of the last peer Net::IP validates this in the input check
    die "ERROR: there is something wrong with the IP range (-s) -- try again!";

  }

  return(\@peers);

}


#########################################################################
# generate prefixes for -u option
#########################################################################
# ipput:
#  - array reference of peers
#  - number of prefixes to be generated // $opt{u}
# output:
#  - hash reference with key = peer IP, value = array reference of prefixes
#########################################################################
sub generate_prefixes {
#########################################################################

  my $peers_array_ref = shift;
  my $number_of_prefixes = shift;

  # hash to be returned at the end
  my %prefixes = ();

  foreach my $peer (@{$peers_array_ref}) {

    my @prefixes = ();

    $peer->[0] =~ /(\d+)\.(\d+)\.(\d+)\.(\d+)/;

    foreach (1 .. $number_of_prefixes) {

      push (@prefixes,"$_.$3.$4.0/24");

    }

    $prefixes{$peer->[0]} = \@prefixes;

  }

  return(\%prefixes);

}


#########################################################################
# generate peer objects
#########################################################################
# input:
#  - router's IP address // Net::IP object $opt{i}
#  - router's AS number // $opt{a}
#  - list of peer's IPs and AS numbers
# output:
#  - array reference with Net::BGP::Peer objects
#########################################################################
sub generate_sessions {
#########################################################################

  my $router_ip = shift;
  my $router_as = shift; 
  my $peers_array_ref = shift;

  my @sessions = ();

  foreach my $peer (@$peers_array_ref) {

    my $peer = Net::BGP::Peer->new(
        Start         => 1,
        ThisID        => "$peer->[0]",
        ThisAS        => "$peer->[1]",
        PeerID        => $router_ip->ip(),
        PeerAS        => "$router_as",
        HoldTime      => 65535,
        KeepAliveTime => 65535,
    );
 
    push (@sessions, $peer);

  }

  return(\@sessions);

}


#########################################################################
# generate update objects
#########################################################################
# input:
#  - array reference of sessions // $sessions_array_ref
#  - prefixes array ref // $opt{c} (may be undef)
#  - prefixes hash ref // $prefixes_hash_ref (may be undef)
# output:
#  - hash reference with key: IPs and value: hashreference with key:
#    "announcement" or "withdraw" and value: array reference 
#    of update objects
#########################################################################
sub generate_updates {
#########################################################################

  my $sessions_array_ref = shift;
  my $cookie_cutter_prefixes = shift;
  my $prefixes_hash_ref = shift;

  my $updates = {};

  foreach my $peer (@{$sessions_array_ref}) {

    my $prefixes_array_ref = undef;
    $prefixes_array_ref = $cookie_cutter_prefixes if $cookie_cutter_prefixes;
    $prefixes_array_ref = $prefixes_hash_ref->{$peer->this_id()};

    my $announcements = 
      &generate_announcements(
        $prefixes_array_ref,
        $peer->this_id(),
        $peer->this_as()
      );

    my $withdraws = 
      &generate_withdraws(
        $prefixes_array_ref
      );

    $updates->{$peer->this_id()}->{announcement} = $announcements;
    $updates->{$peer->this_id()}->{withdraw} = $withdraws;

  }

  return($updates);

}


#########################################################################
# generate withdraws
#########################################################################
# ipput:
#  - array reference of prefixes
# output:
#  - array reference of withdraw objects 
#########################################################################
sub generate_withdraws {
#########################################################################

  my $prefixes_array_ref = shift;

  my @withdraws = ();

  foreach my $prefix (@$prefixes_array_ref) {

    my $withdraw = Net::BGP::Update->new(
      Withdraw    => [ "$prefix" ],
    );

    push (@withdraws, $withdraw);

  }

  return(\@withdraws);

}


#########################################################################
# generate announcements
#########################################################################
# ipput:
#  - array reference of prefixes
#  - sessions IP address
#  - sessions AS number
# output:
#  - array reference of announce objects 
#########################################################################
sub generate_announcements {
#########################################################################

  my $prefixes_array_ref = shift;
  my $peer_ip = shift;
  my $peer_as = shift; 

  my @announcements = ();

  foreach my $prefix (@$prefixes_array_ref) {

    my $announcement = Net::BGP::Update->new(
      NLRI      => [ "$prefix" ],
      AsPath    => Net::BGP::ASPath->new("$peer_as 11 12 13"),
      LocalPref => 100,
      MED       => 200,
      NextHop   => "$peer_ip",
      Origin    => 'INCOMPLETE',
    );

    push (@announcements, $announcement);

  }

  return(\@announcements);

}


#########################################################################
# add sessions to BGP process
#########################################################################
# input:
#  - BGP process object // $bgp
#  - peers IPs and ASs // $sessions_array_ref
#########################################################################
sub add_sessions {
#########################################################################

  my $bgp = shift;
  my $sessions_array_ref = shift;

  foreach my $peer (@$sessions_array_ref) {

    # add Net::BGP::Peer objects to Net::BGP::Process
    $bgp->add_peer($peer);

    &message(\*STDOUT,'added peer: ' . $peer->asstring());

  }

}


#########################################################################
# instruction parser and update timer initiator
#########################################################################
# input:
#  - array reference of session IPs and ASs // $sessions_array_ref
#  - hash reference to updates
#  - timer // $opt{t}
#  - array reference of order sequence // $opt{o} (may be not set)
#  - withdraw option // $opt{w} (may be not set)
#########################################################################
sub parse_instruction_order_and_add_timers {
#########################################################################

  my $sessions_array_ref = shift;
  my $updates = shift;
  my $timer = shift;
  my $order = shift;
  my $withdraw = shift;

  foreach my $peer (@{$sessions_array_ref}) {

    my $timer_for_update = $timer;

    # if order sequence is given, add updates as defined
    if ($order) {

      # keep count of prefixes out there
      my $current_nr_of_prfx_out = 0;

      # predefine start and end int
      my $start = 0;
      my $end = 0;

      # go through each instruction and add new timer
      foreach my $instruction (@{$order}) {

        $instruction =~ /(\d+)([aw]{1})/;

        # for announcements we want to send new 
        # announcements that are not out there yet
        if ($2 eq 'a') {

          # chop of from the beginning of the list 
          # for the numer of prefixes that are still out there
          $start = $current_nr_of_prfx_out;

          # remove from the back until we have the number of 
          # elenemnts in the list that we want to send
          $end = $current_nr_of_prfx_out + $1 - 1;

          # add timer
          &add_update_timers(
            $peer,
            $updates->{$peer->this_id()},
            $start,
            $end,
            undef,
            $timer_for_update,
            $instruction
          );

          # adjust current number of prefixes for next round
          $current_nr_of_prfx_out = $current_nr_of_prfx_out + $1;

        } else {

          # for withdraws we want to send out as many as requested
          # for the last announcements that have been sent
          my $chop_off_from_beginning = $current_nr_of_prfx_out - $1;

          # chop of from the beginning of the list 
          # for the numer of prefixes that are still out there
          $start = $chop_off_from_beginning;
  
          # remove from the back until we have the number of 
          # elenemnts in the list that we want to send
          $end = $chop_off_from_beginning + $1 - 1;

          # add timer
          &add_update_timers(
            $peer,
            $updates->{$peer->this_id()},
            $start,
            $end,
            1,
            $timer_for_update,
            $instruction
          );

          # adjust current number of prefixes for next round
          $current_nr_of_prfx_out = $current_nr_of_prfx_out - $1;

        }

        $timer_for_update = $timer_for_update + $timer;

      }

    } else {

      # if no order sequence, just send all we have once
      &add_update_timers($peer,$updates->{$peer->this_id()},undef,undef,$withdraw,$timer,'all');

    }

  }

}


#########################################################################
# add update timers to sessions
#########################################################################
# input:
#  - peer object // $peer
#  - hash reference to updates of one peer
#  - first element in update array for this selection
#  - last element in update array for this selection
#  - selection whether to withdraw // $opt{w} (may be undef)
#  - timer // $opt{t}
#  - instruction order string
#########################################################################
sub add_update_timers {
#########################################################################

  my $peer = shift;
  my $peers_updates_hash_ref = shift;
  my $start = shift;
  my $end = shift;
  my $withdraw = shift;
  my $timer = shift;
  my $instruction = shift;

  my $update = undef;

  if ($withdraw) {
    $update = 'withdraw';
  } else {
    $update = 'announcement';
  }

  # if start and end index have not been set
  # we dont have a specific order and send all at once 
  unless (defined($start) and defined($end)) {
    $start = 0;
    $end = scalar $#{$peers_updates_hash_ref->{"$update"}};
  }

  # generate timer for each update object in our range
  foreach ($start .. $end) {
 
    my $index = $_; 

    my $sent = undef;
    $peer->add_timer(
      sub {
        \&timer(
          $peers_updates_hash_ref->{"$update"}->[$index],
          $peer,
          $withdraw,
          \$sent,
          $instruction)
      }, $timer
    );

    $peer->set_update_callback(\&my_update_callback);
    $peer->set_notification_callback(\&my_notification_callback);
    $peer->set_error_callback(\&my_error_callback);


  }

}


#########################################################################
# timer function, sending the updates once timer expired
#########################################################################
# input:
#  - update object // $update
#  - peer object // $peer
#  - selection whether to withdraw // $opt{w} (may be undef)
#  - variable to check that updates are only sentout once // $sent
#  - instruction order string // $opt{o} (may be undef)
#########################################################################
sub timer {
#########################################################################

  my $update = shift;
  my $peer = shift;      
  my $withdraw = shift;      
  my $sent_ref = shift;
  my $instruction = shift;

  unless (defined($$sent_ref)) {
    if ($withdraw) {
      my $prefix = $update->withdrawn();
      &message(\*STDOUT,"sending withdraw: @{$prefix}, for peer: " .
            $peer->this_id() . ", instruction: $instruction");
    } else {
      my $prefix = $update->nlri();
      &message(\*STDOUT,"sending announcement: @{$prefix}, for peer: " . 
            $peer->this_id() . ", instruction: $instruction");
    }
    $peer->update($update);
    $$sent_ref = 1;
  }
}



sub my_update_callback {}
sub my_notification_callback {}
sub my_error_callback {}



#########################################################################
# POD documentation
#########################################################################

=head1 NAME

bgp_session_generator.pl - A BGP simmulation script, which 
allows to open a number of BGP sessions to another end host, 
based on a few simple command line options.


=head1 SYNOPSIS

  bgp_session_generator.pl
     -i TARGET-IP \
     -a TARGET-AS \
     -s IP-RANGE \
     -f PEER-AS \
     -t SECS \
     { -c PFX,... | -u NUM-PFXS } \
     [ -w | -o ACTION,ACTION,... ]


=head1 DESCRIPTION

For testing purposes (especially stress testing), it might 
be desireable to facilitate a number of BGP speaking 
services on one system, to be able to test against one 
other end point. This script offers an easy command line 
interface to generate a number of sessions from different 
peers on one host towards another router id.

Based on a range of peer IP addresses (which need to be 
pre-configured as aliases on the systems network interface) and the 
corresponding AS numbers, it will establish sessions to a 
router, defined by its IP and AS number.

Updates to be sent can be defined by their prefixes and 
whether to announce or withdraw them. If the prefixes are not
pre-defined, the script will generate unique prefixes to send 
for each peer in the range. A timer has to be given as interval
for when the updates will be sent out.

A sequence can be specified, to define in which order how many 
prefixes should be announced and withdrawn. If this is not
defined, the prefixes will all be sent at once and only one 
time.


=head1 MANDATORY PARAMETERS

=over 4


=item B<-i> I<TARGET-IP> 

The target router's IP address.


=item B<-a> I<TARGET-AS>

The target router's AS number.


=item B<-s> I<IP-RANGE> 

The range of IP addresses for peering sessions 
to the router (e.g. '10.23.0.1 - 10.23.0.101').

Those addresses need to be specified on the hosts
interface as well (e.g. interface aliases), 
check the documentation of your operating system 
on how to do this.

The user needs to pick the range carefully,
since the script does not inspect the given range 
against the interfaces configured. Furthermore, broadcast
and network addresses won't be recognized 
automatically - everything you specify within 
the range will be used as a peer's IP.


=item B<-f> I<PEER-AS>

The AS number of the first peering session 
(lowest IP address in the C<-s IP-RANGE> range). 
The AS number is incremented for each 
subsequent session.


=item B<-t> I<SECS>

The time between session establishment and each update. 


=item B<-u> I<NUM-PFXS>

The -u option generates unique prefixes for each 
peering session. The provided argument needs to
be an integer between 0 and 255.

Unique prefixes prevent the router from making 
routing decision calculations, since there is always 
only one way to a known prefix.

All prefixes are based on an integer as the first octet, 
from 0 to the number specified in the command.
The session IP's third octet is used as the second octet 
for the prefix and the session IP's fourth octet as 
the third octet for the prefix. All prefixes will be /24's.
E.g. for the peer 10.23.0.1 the first ithree generated
prefixes would be: 1.0.1.0/24, 3.0.1.0/24 and 3.0.1.0/24.

This option is mutually exclusive with the
C<-c PFXS> option, but one of the two must be specified.


=item B<-c> I<PFXS>

The cookie-cutter option, which makes each session use
the same prefixes. As argument it expects a comma-separated 
list of prefixes (e.g. '10.11.12.0/24, 10.12.13.0/24').

Use of this option will increase the amount of computing
for route decisions on the target router, since we will 
have multiple ways to reach the same destination.

This option is mutually exclusive with the
C<-u NUM-PFXS> option, but one of the two must be specified.


=back


=head1 OPTIONS

=over 4


=item B<-h>, B<--help>

View the help message.


=item B<-v>, B<--version>

View the version number.


=item B<-w>

The given prefixes will be withdrawn instead of announced
(announce is default behaviour).

This option is ignored with C<-o ACTION> specified.


=item B<-o> I<ACTION>

Sequence of order and number of prefixes to 
announce/withdraw. For example '2a,2w,4a,3w,15a,16w' - 
this would announce 2, withdraw those 2 again, 
announce 4, withdraw the last 3 of those, announce
another 15 and withdraw all remaining 16 at the end.

Pick your order carefully. The number of announces cannot be higher
than the number of prefixes, and you cannot withdraw more prefixes than
announced. Attempting to do so will result in an error.


=back


=head1 EXAMPLES

To estabish sessions to a targert router at 10.23.0.1 with AS 2342, from all 
IP addresses within the range from 10.23.0.2 to 10.23.0.5, with the corresponding AS 
numbers 65500, 45499, 65498 and 65497, we use the following command:

  ./bgp_session_generator.pl -i 10.23.0.1 -a 2342 -f 65500 \
    -s '10.23.0.2-10.23.0.5' -t 10 -u 5

It will generate 5 unique prefixes per session, as specified via C<-u NUM-PFXS>, and announce them
10 seconds after startup, as specified via C<-t SECS>.

To apply identical prefixes for each session instead of uniquely generated ones, we use 
the C<-c PFXS> parameter instead of C<-u NUM-PFXS>. The following will send out two prefixes for each 
session, specified via C<-c PFXS>, to the target router:

  ./bgp_session_generator.pl -i 10.23.0.1 -a 2342 -f 65500 \
    -s '10.23.0.2-10.23.0.5' -t 10 -c '23.23.23.0/24, 42.42.42.0/24'

To have the prefixes withdrawn instead of announced we also specify the C<-w> switch:

  ./bgp_session_generator.pl -i 10.23.0.1 -a 2342 -f 65500 \
    -s '10.23.0.2-10.23.0.5' -t 10 -c '23.23.23.0/24, 42.42.42.0/24' -w

For more advanced actions in terms of announcements and withdraws, we might also use the C<-o ACTION> 
switch, which allows us to specify an order of updates to be sent for each prefix.
The following action '1a,2a,2w,4a,5w' would announce the first generated prefix, then announce the following 2,
withdrdraw the last 2 again, announce 4 more and then withdraw all 5 again. 

  ./bgp_session_generator.pl -i 10.23.0.1 -a 2342 -f 65500 \
    -s '10.23.0.2-10.23.0.5' -t 10 -u 5 -o '1a,2a,2w,4a,5w'

The script keeps state of the prefixes already sent, hence it will always withdraw the last ones sent out and 
announce the next ones following the ones not withdrawn yet. The total number of prefixes announced at a time 
cannot be greater than the total number of prefixes generated upon startup (as specified via C<-u NUM-PFXS>). 

The same actions are also possible with ideantical prefixes specified via C<-c PFXS>:

  ./bgp_session_generator.pl -i 10.23.0.1 -a 2342 -f 65500 \
    -s '10.23.0.2-10.23.0.5' -t 10 -c '23.23.23.0/24, 42.42.42.0/24' \
    -o '1a,1w,2a,2w,2a,1w,1w'


=head1 AUTHOR

Elisa Jasinska <elisa.jasinska@ams-ix.net>


=head1 COPYRIGHT

Copyright (c) 2009 AMS-IX B.V.

This package is free software and is provided "as is" without express
or implied warranty.  It may be used, redistributed and/or modified
under the terms of the Perl Artistic License (see
http://www.perl.com/perl/misc/Artistic.html)

=cut
