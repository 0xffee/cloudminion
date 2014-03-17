#!/usr/bin/perl

use POSIX qw(strftime);
use FindBin;
use Getopt::Long;
use strict;

my $conf_file = "$FindBin::Bin/../conf/cm_agent.cfg";
my $conf_ref = get_conf();
my %Conf = %$conf_ref;

my ($resource,$uuid,$domain,$threshold,$debug);
my $days_ago = 7;

GetOptions( 'debug'     => \$debug,
            'uuid=s'    => \$uuid,
            'domain=s'  => \$domain,
            'days=s'    => \$days_ago,
            'threshold|t=s' => \$threshold,
            'resource|r=s' => \$resource );


print "DEBUG\n" if ($debug);

if ( ! defined $resource ) {
   help();
   exit 1;
}

if ( (! defined $uuid and ! defined $domain)  or (defined $uuid and defined $domain) ) {
   help();
   exit 1;
}

if ( ! defined $uuid ) {
   if ( $domain eq "all" ) {
       $uuid = $domain;
   } 
   else {
       $uuid = GetUUID($domain);
       if ( $uuid eq "" ) {
           print "Error: Cannot find uuid for domain: $domain\n";
           exit 1; 
       } 
   }
}


if ( ! defined $Conf{cm_sa_dir} ) {
   print "cm_sa_dir is not defined in $conf_file. The tool will now exit.\n";
   exit 1;
}
elsif ( !-d $Conf{cm_sa_dir} ) { 
   print "$Conf{cm_sa_dir} doesn't exist. Cannot read collected data.\n";
   exit 1;
} 

my $previous_days_ref = GetPreviousDays();
my @PreviousDays = @$previous_days_ref;
####################################
my @SA_Files = `ls $Conf{cm_sa_dir}`;
my @UUIDs = ();
if ( $uuid eq "all" ) {
   my @VirshUUIDs = `virsh list --all --uuid`;
   foreach my $line (@VirshUUIDs) {
      chomp($line);
      next if $line =~ m/^$/;
      push @UUIDs, $line;
   }    
}
else {
  @UUIDs = ("$uuid"); 
}

foreach my $uuid_to_check (@UUIDs) {

   print "Checking $uuid_to_check\n" if $uuid eq "all";

   my $instance_data_ref = GetInstanceData($uuid_to_check); 
   my %InstanceData = %$instance_data_ref;

   my $vm_state = "unused";

   my $end_date;  
   my $reported_date;

   my $ix = 0;
   foreach my $current_day (@PreviousDays ) {
       last if $ix == $days_ago; #removing the last day which was added in GetPreviousDays

       my $previous_day = $PreviousDays[$ix+1]; 
       $ix++;

       if ( ! defined $InstanceData{$current_day} or ! defined $InstanceData{$previous_day} ) {
           if (!defined $threshold ) {
               print "   $current_day => n/a\n";
               next;
           }
           else {
               $vm_state = "used";
               last;
           }
       }
       my $current_day_data  = $InstanceData{$current_day};
       my $previous_day_data = $InstanceData{$previous_day};

       my $diff = $current_day_data - $previous_day_data;
       my $daily_traffic = int($diff / 1024 / 1024);


       if ( defined $threshold ) {
           if ($daily_traffic > $threshold ) {
               $vm_state = 'used';
               last;
           }
       }
       else {
           $daily_traffic = comma_me($daily_traffic);
           print "   $current_day => $daily_traffic\n";
       }
   }

   if ( defined $threshold ) {
       #if ( $uuid eq "all" ) {
       #    print "$uuid_to_check: ";
       #}
       print "$vm_state\n";
   }
}
##############################################################################
sub GetInstanceData {
    my $uuid = shift;
    my %InstanceData = ();

    foreach my $date_file (@SA_Files) {
        chomp($date_file);
        my @File = `cat $Conf{cm_sa_dir}/$date_file | grep $uuid`;
        foreach my $line (@File) {
            chomp($line);
            my ($collected_resource, $epoch, $collected_uuid, $data1,$data2,$data3) = split(/:/,$line);
            if ($collected_resource eq $resource and $collected_uuid eq $uuid) {
                if ( $resource eq "net" ) {
                    my $data = $data1 + $data2;
                    $InstanceData{$date_file} = $data;
                }
            }
       }
   }
   return(\%InstanceData);
}

##############################################################################
sub GetPreviousDays {
   my $thisday = time;
   my $day_counter = 1;
   my @PreviousDays = ();

   while ( $day_counter <= $days_ago ) {
       my $PreviousDay = $thisday - $day_counter * 24 * 60 * 60;
       $PreviousDay = strftime "%Y%m%d", ( localtime($PreviousDay) );
       push @PreviousDays, $PreviousDay;
       $day_counter++;
   }

   # add 1 extra day which will be used for calculating the last day
   # this day will be removed later
   my $PreviousDay = $thisday - $day_counter * 24 * 60 * 60;
   $PreviousDay = strftime "%Y%m%d", ( localtime($PreviousDay) );
   push @PreviousDays, $PreviousDay;

   return(\@PreviousDays);
}
##############################################################################
sub GetUUID {
    my $domain = shift;
    my $uuid;

    my @DomainInfo = `virsh dominfo $domain`;
    foreach my $line (@DomainInfo) {
        chomp($line);
        if ($line =~ m/UUID:\s+(\S+)/) {
           $uuid = $1;
           last;
        }
    } 
    return $uuid;
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
sub comma_me {
local $_  = shift;
1 while s/^(-?\d+)(\d{3})/$1,$2/;
return $_;
}
##############################################################################
sub help {
    print "Usage:  --uuid <uuid> | --domain <domain>\n";
    print "        --resource <resource>\n";
    print "        --days <days_ago>\n";
    print "        --threshold <threshold value>\n";
}
