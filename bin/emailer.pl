#!/usr/bin/perl

use Mail::Sendmail;
use strict;
use Getopt::Std;

my $base_dir  = "/x/itools/cloud_minion";
my $conf_file = "${base_dir}/conf/cm.cfg";

if ( ! -f $conf_file ) {
    print "Error: Missing $conf_file\n";
    exit 1;
}
my $conf_ref = get_conf();
my %Conf = %$conf_ref;


my $from = $Conf{email_from};
my $smtp = $Conf{email_smtp};

if ( $from eq "" ) {
    print "Error: Missing email_from in $conf_file\n";
    exit 1;
}
if ( $smtp eq "" ) {
    print "Error: Missing email_smtp in $conf_file\n";
    exit 1;
}

my %options;
my $message;
my $subject;
my $send_to;
my $file;

getopts('t:S:f:', \%options);

if ( defined "$options{S}" and $options{S} ne "" ) {
   $subject = $options{S};
}
else {
   print_help();
   exit;
}

if ( defined "$options{t}" and $options{t} ne "" ) {
   $send_to = $options{t};
}
else {
   print_help();
   exit;
}

if ( defined "$options{f}" and $options{f} ne "" ) {
   $file = $options{f};
}
else {
   print_help();
   exit;
}

$message = `cat $file`;
email($send_to, $subject, $message);

##############################################################
sub email {
   my $send_to = shift;
   my $subject = shift;
   my $message = shift;

   my %mail = (
      To      => $send_to,
      From    => $from,
      Subject => $subject,
      'X-Mailer' => "Mail::Sendmail version $Mail::Sendmail::VERSION",
    );

    $mail{smtp} = $smtp;
    $mail{'X-custom'} = 'My custom additionnal header';
    $mail{'mESSaGE : '} = "$message";
    $mail{Date} = Mail::Sendmail::time_to_date( time() );
    if (sendmail %mail) {  }
    else { print "Error sending mail: $Mail::Sendmail::error \n" }
}
#############################################################
sub get_conf {
   my %conf = ();
   my @CONF = `cat $conf_file`;
   foreach my $line (@CONF) {
      chomp($line);
      if ( $line =~ m/(.*)=(.*)/ ) {
          my $conf_key = $1;
          my $conf_value = $2;
          $conf_value =~ s/^"//;
          $conf_value =~ s/"$//;
          $conf{$conf_key} = $conf_value;
      }
   }
   return (\%conf);
}
#############################################################
sub print_help {
  print "Usage:  -t <TO  list of email addresses>\n";
  print "        -S <subject>\n";
  print "        -f <filename to email>\n";
}
