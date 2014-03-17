#!/usr/bin/perl

use strict;
use warnings;
use DBI;
use CGI;
use JSON::XS;
use FindBin;
use Getopt::Long;

my $conf_file = "$FindBin::Bin/../conf/cm.cfg";
my $conf_ref = get_conf();
my %Conf = %$conf_ref;

my $q = CGI->new;
print $q->header("application/json");

my $req_m = $q->request_method;
logger("$req_m");

sub GET($$) {
   my ($path, $code) = @_;
   return unless $q->request_method eq 'GET' or $q->request_method eq 'HEAD';
   return unless $q->path_info =~ $path;
   $code->();
   exit;
}

sub POST($$) {
   my ($path, $code) = @_;
   return unless $q->request_method eq 'POST';
   return unless $q->path_info =~ $path;
   $code->();
   exit;
}

eval {
GET qr{^/compute/(.*)/list$} => sub {
   my $compute_host = $1;
   my $Hash_ref = GetVMs($compute_host);
   my %Hash = %$Hash_ref;
   my $json = encode_json \%Hash;
   my $log_message = "GET compute/${compute_host}/list : JSON = $json";
   logger("$log_message") if ($Conf{debug} =~ m/true/i);
   print $json;
};
POST qr{^/compute/(.*)/update$} => sub {
   my $compute_host = $1;
   my $log_message = "POST compute/${compute_host}/update ";
   logger("$log_message") if ($Conf{debug} =~ m/true/i);

   my $json  = JSON::XS->new->utf8;
   my $decoded_json = $json->decode( $q->param('POSTDATA') );
   #my $decoded_json = $q->param('POSTDATA');

   my $log_message = "POST compute/${compute_host}/update : JSON = $decoded_json ";
   logger("$log_message") if ($Conf{debug} =~ m/true/i);

   my %UUIDs = %$decoded_json;
   if ( keys %UUIDs > 0 ) {
      UpdateDB($compute_host, \%UUIDs);  
   }
   else {
       my $log_message = "Updating compute_host $compute_host but empty json received";
       logger("$log_message") if ($Conf{debug} =~ m/true/i);
   }
};

exit;
};
##############################################

sub GetVMs {
    my $compute_host = shift;
    my %Hash = ();

    logger("Querying DB for compute_host $compute_host") if $Conf{verbose} eq "true";
    logger("Connecting to $Conf{lifetime_db};host=$Conf{cm_db_host};port=$Conf{cm_db_port} - with $Conf{lifetime_user} / $Conf{lifetime_password}") if $Conf{verbose} eq "true";

    my $dbh = DBI->connect("DBI:mysql:database=$Conf{lifetime_db};host=$Conf{cm_db_host};port=$Conf{cm_db_port}", "$Conf{lifetime_user}", "$Conf{lifetime_password}",
          {'RaiseError' => 1 });

    my $sql = "select uuid, expiration_date from instance_lifetimes where deleted = 0 and compute_host = '$compute_host'";
    my $sth = $dbh->prepare($sql) or die "Couldn't prepare query";
    $sth->execute();
    my $row_number = $sth->rows;
    #my $result = $sth->fetchrow_hashref();
    if ( $row_number > 0 ) {
        logger("Found $row_number records for compute_host $compute_host in $Conf{lifetime_db}") if $Conf{verbose} eq "true";
        while (my @rows = $sth->fetchrow_array()) {
             my $uuid = $rows[0];
             my $expiration_date = $rows[1];
             #$Hash{$uuid} = $expiration_date;
             $Hash{$uuid} = { 'uuid' => $uuid, 'expiration_date' => $expiration_date };
         
        }
    }
    else {
        logger("Missing compute_host $compute_host in $Conf{lifetime_db}") if $Conf{verbose} eq "true";
        $Hash{0} = { 'uuid' => '0', 'expiration_date' => 'n/a' };
    }
    $sth->finish();
    $dbh->disconnect();

    return (\%Hash);

}

##############################################################################
sub UpdateDB {
   my $compute_host = shift; 
   my $UUIDs_ref    = shift;
   my %UUIDs        = %$UUIDs_ref;
   my $state;       #???
   my $deleted      = 0; #???
   my $log_message = "Update: compute=$compute_host : ";
   logger("$log_message") if $Conf{verbose} eq "true";

   my $dbh = DBI->connect("DBI:mysql:database=$Conf{lifetime_db};host=$Conf{cm_db_host};port=$Conf{cm_db_port}", "$Conf{lifetime_user}", "$Conf{lifetime_password}",
      {'RaiseError' => 1 });

   for my $uuid ( keys %UUIDs) {
       my $unused = $UUIDs{$uuid}{unused};

       #Check whether uuid is in DB
       my $sql = "select uuid from instance_lifetimes where uuid = '$uuid'";
       my $sth = $dbh->prepare($sql) or die "Couldn't prepare query";
       $sth->execute();
       $sth->rows;
       $sth->finish();
       my $row_number = $sth->rows;

       if ( $row_number == 0 ) {
           $sql = "insert into instance_lifetimes (uuid,last_check,unused,compute_host,state,deleted) values ('$uuid', NOW(), '$unused', '$compute_host', '$state', '$deleted')";
       }
       else {
           $sql = "update instance_lifetimes set last_check = NOW(), unused = '$unused' where uuid = '$uuid'";
       }

       my $sth = $dbh->prepare($sql);
       $sth->execute();
       $sth->finish();
       $log_message .= "$uuid=(unused=$unused) ";

   }

   $dbh->disconnect();
   logger("$log_message") if ($Conf{debug} =~ m/true/i);
}

##############################################################################
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
##############################################################################
sub logger {
    my $message = shift;
    my $date = `date`;
    chomp($date);
    my $log_file = "/var/log/cloudminion/cm-api.log";
    if ( defined $Conf{api_log_file} ) {
       $log_file = $Conf{api_log_file};
    }
    open(LOG, ">>${log_file}");
    print LOG "$date: $message\n";
    close(LOG);
}
