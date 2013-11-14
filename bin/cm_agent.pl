#!/usr/bin/perl

use File::Path qw( make_path );
use DBI;
use strict;

my $base_dir = "/x/itools";
my $conf_file = "${base_dir}/conf/cm_agent.cfg";
my $conf_ref = get_conf();
my %Conf = %$conf_ref;

my $current_time = time();
my $unused_login_sec = ( $Conf{unused_last_login_days} * 86400 );

my $compute_host = `hostname`;
chomp($compute_host);

my $instances_ref = GetInstances();
my %Instances = %$instances_ref;

my $dbh = DBI->connect("DBI:mysql:database=$Conf{lifetime_db};host=$Conf{db_host};port=$Conf{db_port}", "$Conf{lifetime_db_user}", "$Conf{lifetime_db_password}",
          {'RaiseError' => 1 });    


foreach my $domain (keys %Instances) {
    my $uuid = $Instances{$domain};

    my $expiration_date = GetVMExpirationDate($uuid);
    if ( ! $expiration_date ) {
        print "Checking $domain ($uuid)\n";
        my $unused = GuestMountAndCheck($domain);
        if ($unused == 1 ) {
             print "There was error checking $domain\n";
        }
        else {
             UpdateDB($uuid, $unused);
        }
    }
    else {
        print "Instance: $domain ($uuid) has an expiration date\n";
    }
}

$dbh->disconnect();

##############################################################################
##############################################################################

sub GetInstances {
    my %Instances = ();
    
    my @LibvirtXML_Files = `ls $Conf{instances_dir}/*/libvirt.xml`; 
    foreach my $xml_file ( @LibvirtXML_Files ) {
        chomp($xml_file);
        my ($domain, $uuid);
        my @LibvirtXML = `cat $xml_file`;
        foreach my $line ( @LibvirtXML ) {
            if ( $line =~ m/<name>(.*)<\/name>/ ) {
               $domain = $1;
            }
            elsif ( $line =~ m/<uuid>(.*)<\/uuid>/ ) {
               $uuid = $1;
            }
        }
        if ( $domain ne "" and $uuid ne "" ) {
            $Instances{$domain} = $uuid;
        }
    }
    return(\%Instances);
}

##############################################################################
sub GetVMExpirationDate {
   my $uuid = shift;

   my $sql = "select expiration_date from instance_lifetimes where uuid = '$uuid'";
   my $sth = $dbh->prepare($sql) or die "Couldn't prepare query";
   $sth->execute();
   my $result = $sth->fetchrow_hashref();
   $sth->finish();

   my $expiration_date = $result->{expiration_date};
   return($expiration_date);
}
##############################################################################
sub UpdateDB {
   my $uuid = shift;
   my $unused = shift;
   my $state; #???
   my $deleted = 0; #???

   #Check whether uuid is in DB
   my $sql = "select uuid from instance_lifetimes where uuid = '$uuid'";
   my $sth = $dbh->prepare($sql) or die "Couldn't prepare query";
   $sth->execute();
   $sth->rows;
   $sth->finish();
   my $row_number = $sth->rows;

   if ( $row_number == 0 ) {
       print "Inserting ... \n";
       $sql = "insert into instance_lifetimes (uuid,last_check,unused,compute_host,state,deleted) values ('$uuid', NOW(), '$unused', '$compute_host', '$state', '$deleted')";
   }
   else {
       print "Updating ... \n";
       $sql = "update instance_lifetimes set last_check = NOW(), unused = '$unused' where uuid = '$uuid'";
   }

   my $sth = $dbh->prepare($sql);
   $sth->execute();
   $sth->finish();
}

##############################################################################
sub GuestMountAndCheck {
    my $domain = shift;
    my $unused = "false";
    my $wtmp_file = "$Conf{guestmount_dir}/var/log/wtmp";

    if ( !-d $Conf{guestmount_dir} ) {
        make_path $Conf{guestmount_dir} or die "Failed to create path: $Conf{guestmount_dir}";
    } 
    # check whether guestmount dir is already mounted
    my $result = `cat /proc/mounts | grep $Conf{guestmount_dir}`;
    if ($result) {
        print "$Conf{guestmount_dir} is still mounted. The agent will exit.\n";
        return(1);
    }

    # guestmount the domain
    system("guestmount -d $domain -i --ro $Conf{guestmount_dir}");
    my $result = `cat /proc/mounts | grep $Conf{guestmount_dir}`;
    if ( ! $result) {
        print "There was a problem mounting $domain\n";
        return(1);
    }

    #############################################################    
    # Run various check on the mounted domain

    # check last login
    if ( -f "$wtmp_file" ) {
        my $file_mod_time = `stat -c %Y $wtmp_file`;
        chomp($file_mod_time);
        if ( $file_mod_time < ($current_time - $unused_login_sec ) ) {
             $unused = "true";
        }
    } 

    # unmount the doamin
    system("fusermount -u $Conf{guestmount_dir}");

    my $result = `cat /proc/mounts | grep $Conf{guestmount_dir}`;
    if ($result) {
        print "$Conf{guestmount_dir} is still mounted. The agent will exit.\n";
        return(1);
    }

    return($unused);
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

