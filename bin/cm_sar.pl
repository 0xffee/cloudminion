#!/usr/bin/perl

use strict;
use POSIX qw(strftime);
use FindBin;
use JSON::XS;
use lib "$FindBin::Bin/../lib";
use HTTP::Tiny;
use Getopt::Long;

my $conf_file = "$FindBin::Bin/../conf/cm_agent.cfg";
my $conf_ref = get_conf();
my %Conf = %$conf_ref;

my ($show,$resource,$uuid,$domain,$updatedb,$debug,$verbose );
my ($threshold,$range,$deviation,$bytes,$direction);
my $days_ago = 7;


GetOptions( 'debug'         => \$debug,
            'verbose|v'     => \$verbose,
            'uuid=s'        => \$uuid,
            'domain=s'      => \$domain,
            'show=s'        => \$show,
            'days=s'        => \$days_ago,
            'threshold|t=s' => \$threshold,
            'resource|r=s'  => \$resource,
            'direction=s'   => \$direction,
            'bytes|b'       => \$bytes,
            'deviation=s'   => \$deviation,
            'range=s'       => \$range,
            'updatedb'      => \$updatedb );


print "DEBUG\n" if ($debug);

if ( ! defined $resource ) {
   help();
   exit 1;
}

if ( ! defined $show or ( $show ne "traffic" and $show ne "state" ) ) {
   print "Missing or incorrect --show argument\n";
   help();
   exit 1;
}
if ( $show eq "state" and ( ! defined $threshold and ! defined $range and ! defined $deviation ) ) {
   print "'--show state' requires one or combination of --threshold, --range, --deviation\n";
   help();
   exit 1;
}

my ($threshold_value, $threshold_format);;
if ( defined $threshold ) {
   if ( $threshold =~ m/(\d+)$/ ) {
       $threshold_format = "bytes";
       $threshold_value = $1;
   }
   elsif ( $threshold =~ m/(\d+)k$/ ) {
       $threshold_format = "kilo";
       $threshold_value = $1;
   }
   elsif ( $threshold =~ m/(\d+)m$/ ) {
       $threshold_format = "mega";
       $threshold_value = $1;
   }
   else {
      help();
      exit;
   }
}


if ( defined $direction ) {
    if ( $direction ne "ingress" and $direction ne "egress" and $direction ne "any" and $direction ne "both" ) {
       print "Incorrect --direction value\n";
       help();
       exit;
    }
}
else {
    $direction = "both";
}

my ($deviation_threshold_format, $deviation_threshold_value);
if ( defined $deviation ) {
    if ( $deviation =~ m/(\d+)$/ ) {
       $deviation_threshold_format = "bytes";
       $deviation_threshold_value = $1;
    }
    elsif ( $deviation =~ m/(\d+)k$/ ) {
       $deviation_threshold_format = "kilo";
       $deviation_threshold_value = $1;
   }
   elsif ( $deviation =~ m/(\d+)m$/ ) {
       $deviation_threshold_format = "mega";
       $deviation_threshold_value = $1;
   }
   else {
       help();
       exit;
   }
}

my ($range_format, $range_value);
if ( defined $range ) {
    if ( $range =~ m/(\d+)$/ ) {
        $range_format = "bytes";
        $range_value = $1;
    }
    elsif ( $range =~ m/(\d+)k$/ ) {
        $range_format = "kilo";
        $range_value = $1;
    }
    elsif ( $range =~ m/(\d+)m$/ ) {
        $range_format = "mega";
        $range_value = $1;
    }
    else {
        help();
        exit;
    }
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

my %UUIDs = ();

foreach my $uuid2check (@UUIDs) {

   print "Checking $uuid2check\n" if $uuid eq "all";

   my $instance_data_ref = GetInstanceData($direction, $uuid2check);
   my %InstanceData = %$instance_data_ref;

   my $vm_state = "unused";

   my $end_date;
   my $reported_date;

   my @Data = ();
   my $ix = 0;
   foreach my $current_day (@PreviousDays ) {
       last if $ix == $days_ago; #removing the last day which was added in GetPreviousDays

       my $previous_day = $PreviousDays[$ix+1];
       $ix++;

       if ( ! defined $InstanceData{$current_day} or ! defined $InstanceData{$previous_day} ) {
           if ( $show eq "traffic" ) {
               if ( defined $updatedb ) {
                  $UUIDs{$uuid2check}{$current_day} = 'n/a';
               }
               else {
                  print "   $current_day => n/a\n";
               }
               next;
           }
           elsif ( $show eq "state" ) {
               $vm_state = "used";
               last;
           }
           else {
               help();
               exit;
           }
       }
       my $current_day_data  = $InstanceData{$current_day};
       my $previous_day_data = $InstanceData{$previous_day};

       # Daily traffic
       my $daily_traffic = $current_day_data - $previous_day_data;
       push @Data, $daily_traffic;

       if ( $threshold_format eq "kilo" ) {
          $daily_traffic = int($daily_traffic / 1024 );
       }
       elsif ( $threshold_format eq "mega" ) {
          $daily_traffic = int($daily_traffic / 1024 / 1024);
       }
       elsif ( $threshold_format eq "giga" ) {
          $daily_traffic = int($daily_traffic / 1024 / 1024 / 1024);
       }

       if ( $show eq "state" and defined $threshold and $vm_state eq "unused" ) {
           if ($daily_traffic > $threshold_value ) {
               $vm_state = 'used';
               #last;
           }
       }
       elsif ( $show eq "traffic" ) {
           if ( defined $updatedb ) {
              $UUIDs{$uuid2check}{$current_day} = $daily_traffic;
           }
           else {
              $daily_traffic = comma_me($daily_traffic);
              print "   $current_day => $daily_traffic\n";
           }
       }
   }
   ## Standard Deviation
   if ( (defined $deviation or defined $verbose) and @Data > 1 ) {
       my $stdev = int(stdev(\@Data));
       my $postfix = "bytes";
       if ( $deviation_threshold_format eq "bytes" ) {
           $stdev = int($stdev);
       }
       elsif ( $deviation_threshold_format eq "kilo" ) {
            $stdev = int($stdev / 1024 );
            $postfix = "kilobytes";
       }
       elsif ( $deviation_threshold_format eq "mega" ) {
           $stdev = int($stdev / 1024 / 1024 );
            $postfix = "megabytes";
       }

       if ( defined $deviation and $vm_state eq "unused" and $stdev > $deviation_threshold_value ) {
           $vm_state = "used";
       }
       if ( $verbose ) {
           $stdev = comma_me($stdev);
           print "   Standard Deviation: $stdev $postfix\n";
       }
   }

   ## Range
   if ( (defined $range or defined $verbose) and @Data > 1 ) {
       @Data = sort { $a <=> $b } @Data;
       my $min = @Data[0];
       my $max = @Data[-1];
       my $difference = $max - $min;
       my $postfix = "bytes";
       if ( $range_format eq "bytes" ) {
           $difference = int($difference);
       }
       elsif ( $range_format eq "kilo" ) {
           $difference = int($difference / 1024);
           $postfix = "kilobytes";
       }
       elsif ( $range_format eq "mega" ) {
           $difference = int($difference / 1024 / 1024);
           $postfix = "megabytes";
       }
       if ( defined $range and $vm_state eq "unused" and $difference > $range_value ) {
           $vm_state = "used";
       }
       if ( $verbose ) {
           $difference = comma_me($difference);
           print "   Range: $difference $postfix\n";
       }
   }


   if ( $show eq "state" ) {
       print "$vm_state\n";
   }

}


if ( defined $updatedb ) {
     UpdateDB(\%UUIDs);
}
##############################################################################
sub UpdateDB {
    my $UUIDs_ref = shift;
    my %UUIDs = %$UUIDs_ref;
    my $json = JSON::XS->new->utf8;
    $json = encode_json($UUIDs_ref);

    my $url  = "$Conf{cm_api_host}/$Conf{az}/$Conf{cm_api}/sa/$resource/update";
    print "DEBUG: Updating NetworkUtilization, Post: $url\n" if ($debug);
    print "DEBUG: json = $json\n" if ($debug);

    my $http = HTTP::Tiny->new;
    $http->timeout(10);
    my $response = $http->request('POST', $url, {
             content => $json,
             headers => {'content_type' => 'application/json'},
    });

    if ( $response->{success} ) {
        print "Debug: successfuly posted data\n" if ($debug);
    }
    else {
        print "$response->{status} $response->{reason}\n";
        print "Failed to connect to API server. Make sure cm_api is set in $conf_file\n";
        exit 1;
    }
}
##############################################################################

sub GetInstanceData {
    my $direction = shift;
    my $uuid = shift;
    my %InstanceData = ();
    print "direction = $direction\n" if ($debug);

    foreach my $date_file (@SA_Files) {
        chomp($date_file);
        my @File = `cat $Conf{cm_sa_dir}/$date_file | grep $uuid`;
        foreach my $line (@File) {
            chomp($line);
            my ($collected_resource, $epoch, $collected_uuid, $data1,$data2,$data3) = split(/:/,$line);
            if ($collected_resource eq $resource and $collected_uuid eq $uuid) {
                if ( $resource eq "net" ) {
                    my $data;
                    if ( $direction eq "ingress" ) {
                        $data = $data1;
                    }
                    elsif ( $direction eq "egress" ) {
                        $data = $data2;
                    }
                    elsif ( $direction eq "both" ) {
                       $data = $data1 + $data2;
                    }

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
sub stdev{
    my $data_ref = shift;
    my @Data = @$data_ref;
    #Get Average
    my $total = 0;
    foreach (@Data) {
        $total += $_;
    }
    my $average = $total/@Data;
    # Get Standard Deviation
    my $sqtotal = 0;
    foreach (@Data) {
        $sqtotal += ($average - $_) ** 2;
    }
    my $std = ($sqtotal / (@Data - 1)) ** 0.5;
    return $std;
}
##############################################################################
sub help {
    print "Usage:  --uuid <uuid> | --domain <domain>\n";
    print "        --show <state|traffic>\n";
    print "        --resource <resource>\n";
    print "        --days <days_ago>\n";
    print "        --direction <both | any | ingress | egress >\n";
    print "        --threshold <threshold value> in bytes | kilobytes | megabytes\n";
    print "        --deviation <threshold value in bytes |Kbytes>\n";
    print "        --range <threshold value> in bytes | kilobytes | megabytes\n";
    print "        --updatedb\n";
    print "        --debug\n";
    print "        --verbose|-v\n";
}
