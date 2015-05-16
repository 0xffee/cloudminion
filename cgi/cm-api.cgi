#!/usr/bin/perl

use strict;
use warnings;
use DBI;
use CGI;
use JSON::XS;
use FindBin;
use Getopt::Long;

my $cell = "cell-01";

my $conf_file = "$FindBin::Bin/../../conf/${cell}_cm.cfg";
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

   $log_message = "POST compute/${compute_host}/update : JSON = $decoded_json ";
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
POST qr{^/sa/net/update$} => sub {
   my $json  = JSON::XS->new->utf8;
   my $decoded_json = $json->decode( $q->param('POSTDATA') );

   my $log_message = "POST sa/net/update : JSON = $decoded_json ";
   logger("$log_message") if ($Conf{debug} =~ m/true/i);

   my %UUIDs = %$decoded_json;
   if ( keys %UUIDs > 0 ) {
       UpdateSA_DB("net", \%UUIDs );
   }
   else {
       my $log_message = "Updating sa/net but empty json received";
       logger("$log_message") if ($Conf{debug} =~ m/true/i);
   }
};

GET qr{^/update-cm/(.*)/(.*)$} => sub {
   my $uuid = $1;
   my $expiration_date = $2;

   my $log_message = "POST cm-update : cell = $cell : uuid = $uuid : expiration_date = $expiration_date ";
   logger("$log_message") if ($Conf{debug} =~ m/true/i);

   my $status = UpdateCM_ExpirationDate($cell, $uuid, $expiration_date );
   if ( $status eq "success" ) {
       print "Success";
   }
   else {
       print "Failed: $status";
       my $log_message = "update-cm: Failed to update $cell, $uuid, $expiration_date";
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
    logger("Connecting to $Conf{lifetime_db};host=$Conf{cm_db_host};port=$Conf{cm_db_port} - with $Conf{cm_user} / $Conf{cm_password}") if $Conf{verbose} eq "true";

    my $dbh = DBI->connect("DBI:mysql:database=$Conf{lifetime_db};host=$Conf{cm_db_host};port=$Conf{cm_db_port}", "$Conf{cm_user}", "$Conf{cm_password}",
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

   my $dbh = DBI->connect("DBI:mysql:database=$Conf{lifetime_db};host=$Conf{cm_db_host};port=$Conf{cm_db_port}", "$Conf{cm_user}", "$Conf{cm_password}",
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
sub UpdateCM_ExpirationDate {
    my $cell = shift;
    my $uuid = shift;
    my $new_expiration_time = shift;
    my $interval_number = 0;
    my $status;
    my $log_message;


    if ($new_expiration_time eq "one_month" ) {
       $interval_number = 1;
    }
    elsif ($new_expiration_time eq "three_months" ) {
       $interval_number = 3;
    }
    elsif ($new_expiration_time eq "one_year" ) {
       $interval_number = 12;
    }
    my $new_expiration_value;
    if ($new_expiration_time eq "never_expires" ) {
       $new_expiration_value = "0000-00-00";
    }
    else {
       $new_expiration_value = "DATE_ADD(CURDATE(), interval $interval_number month)";
    }


   
    my $dbh = DBI->connect("DBI:mysql:database=$Conf{lifetime_db};host=$Conf{cm_db_host};port=$Conf{cm_db_port}", "$Conf{cm_user}", "$Conf{cm_password}",
      {'RaiseError' => 1 });

    my $sql = "select uuid from instance_lifetimes where uuid = '$uuid'";
    my $sth = $dbh->prepare($sql) or die "Couldn't prepare query";
    $sth->execute();
    $sth->rows;
    $sth->finish();
    my $row_number = $sth->rows;
    if ( $row_number == 0 ) {
        $status = "no such uuid: $uuid";
        $log_message = "update-cm: no such uuid: $uuid";
    }
    else {
        my $sql = qq[update instance_lifetimes set expiration_date = $new_expiration_value where uuid = '$uuid'];
        my $sth = $dbh->prepare($sql);
        $sth->execute();
        $sth->finish();
        $log_message = "update-cm: updated $uuid with $new_expiration_time";
        $status = "success";
    }

    $dbh->disconnect();
    return($status);
}
##############################################################################
sub UpdateSA_DB {
   my $resource     = shift;
   my $UUIDs_ref    = shift;
   my %UUIDs        = %$UUIDs_ref;

   my $db_table;
   if ( $resource eq "net" ) {
       $db_table = "network_utilization";
   }

   my $log_message = "Update: SA/NET : ";
   logger("$log_message") if $Conf{verbose} eq "true";

   # place colums in placeholders, number of days = 14 
   my @ColNames = ();
   for ( my $num=1; $num<=14; $num++ ) {
       push @ColNames, $num;
   }
   my $ColNames = join(', ', map { "day$_" } 1 .. @ColNames);


   my $dbh = DBI->connect("DBI:mysql:database=$Conf{lifetime_db};host=$Conf{cm_db_host};port=$Conf{cm_db_port}", "$Conf{cm_user}", "$Conf{cm_password}",
      {'RaiseError' => 1 });

   for my $uuid ( keys %UUIDs) {
       my @DaysValues = ();
       foreach my $key ( reverse sort keys $UUIDs{$uuid} ) {
            my $value = $UUIDs{$uuid}{$key};
            push @DaysValues, $value;
       }
       my $placeholders = join ", ", ("?") x @DaysValues;
                        
       #Check whether uuid is in DB
       my $sql = "select uuid from $db_table where uuid = '$uuid'";
       my $sth = $dbh->prepare($sql) or die "Couldn't prepare query";
       $sth->execute();
       $sth->rows;
       $sth->finish();
       my $row_number = $sth->rows;

       if ( $row_number > 0 ) {
           my $sql = "delete from $db_table where uuid = '$uuid'";
           my $sth = $dbh->prepare($sql);
           $sth->execute();
           $sth->finish(); 
       }

       $sql = "insert into $db_table (uuid,$ColNames) values ('$uuid',$placeholders)";
       my $sth = $dbh->prepare($sql);
       $sth->execute(@DaysValues);
       $sth->finish();
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
