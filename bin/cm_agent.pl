#!/usr/bin/perl

my $base_dir = "/x/itools";

use File::Path qw( make_path );
use DBI;
use Getopt::Long;
use strict;
require "$base_dir/conf/Rules.pm";

my $conf_file = "${base_dir}/conf/cm_agent.cfg";
my $conf_ref = get_conf();
my %Conf = %$conf_ref;

my $Rules_ref = Rules::GetAllRules();
my %Rules = %$Rules_ref;

my $GuestMountRuleExists = 0;
my $HypervisorRuleExists = 0;

for my $key (keys %Rules) {
    if ( $Rules{$key}{Type} eq "GuestMount" ) {
         $GuestMountRuleExists = 1;
    }
    elsif ( $Rules{$key}{Type} eq "Hypervisor" ) {
         $HypervisorRuleExists = 1;
    }
}

my $debug;
GetOptions( 'debug'   => \$debug );

my $rules_boolean_operator = "or"; # Default operator
my $check_unused_vms = "false";

if ( $Conf{rules_boolean_operator} ) {
   $rules_boolean_operator = $Conf{rules_boolean_operator};
}
if ( $Conf{check_unused_vms} ) {
   $check_unused_vms = $Conf{check_unused_vms};
}


my $current_time = time();

my $compute_host = `hostname`;
chomp($compute_host);

my $instances_ref = GetInstances();
my %Instances = %$instances_ref;

my $dbh = DBI->connect("DBI:mysql:database=$Conf{lifetime_db};host=$Conf{db_host};port=$Conf{db_port}", "$Conf{lifetime_db_user}", "$Conf{lifetime_db_password}",
          {'RaiseError' => 1 });


foreach my $domain (keys %Instances) {
    my $uuid = $Instances{$domain};
    my %UnusedResult1 = ();
    my %UnusedResult2 = ();
    my $final_result;
    my $expiration_date = GetVMExpirationDate($uuid);

    if ( ! $expiration_date or $check_unused_vms eq "true" ) {
        print "Checking $domain ($uuid)\n";
        if ( $GuestMountRuleExists == 1 ) {
            my $UnusedResult_ref = GuestMountAndCheck($domain);
            %UnusedResult1 = %$UnusedResult_ref;
        }
        if ( $HypervisorRuleExists == 1 ) {
            my $UnusedResult_ref = HypervisorCheck($domain);
            %UnusedResult2 = %$UnusedResult_ref;
        }

        my %UnusedResult = (%UnusedResult1, %UnusedResult2);
        for my $key ( keys %UnusedResult ) {
            print "DEBUG: RuleResult: $key = $UnusedResult{$key}\n" if ($debug);
            if ( ! $final_result ) {
                $final_result = $UnusedResult{$key};
                next;
            }
            if ( $rules_boolean_operator eq "or" ) {
                if ( $final_result eq "true" or $UnusedResult{$key} eq "true" ) {
                    $final_result = "true";
                }
            } elsif ( $rules_boolean_operator eq "and" ) {
                if ( $final_result eq "true" and $UnusedResult{$key} eq "true" ) {
                    $final_result = "true";
                } else {
                    $final_result = "false";
                }
            }
        }
        if ( $final_result ) {
           UpdateDB($uuid, $final_result);
           print "DEBUG: uuid = $final_result\n" if ($debug);
        }
    }
    else {
        print "Instance: $domain ($uuid) has an expiration date\n";
    }

    #last;
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
    my %UnusedResult = ();

    if ( !-d $Conf{guestmount_dir} ) {
        make_path $Conf{guestmount_dir} or die "Failed to create path: $Conf{guestmount_dir}";
    }
    # check whether guestmount dir is already mounted
    my $result = `cat /proc/mounts | grep $Conf{guestmount_dir}`;
    if ($result) {
        print "$Conf{guestmount_dir} is still mounted. The agent will exit.\n";
        #return(1);
        return(\%UnusedResult);
    }

    # guestmount the domain
    system("guestmount -d $domain -i --ro $Conf{guestmount_dir}");
    my $result = `cat /proc/mounts | grep $Conf{guestmount_dir}`;
    if ( ! $result) {
        print "There was a problem mounting $domain\n";
        #return(1);
        return(\%UnusedResult);
    }

    #############################################################
    # Run rules on the mounted domain

    for my $key (keys %Rules) {
        my $unused = "false";
        if ( $Rules{$key}{Type} eq "GuestMount" ) {
            if ( $Rules{$key}{Function} ) {
                $unused = RunFunction($domain, $Rules{$key}{Type}, $Rules{$key}{Function}, $Rules{$key}{FileName}, $Rules{$key}{UnusedCondition}, $Rules{$key}{UnusedValue} );
            }
            elsif ( $Rules{$key}{Command} ) {
                $unused = RunCommand($domain, $Rules{$key}{Type}, $Rules{$key}{Command}, $Rules{$key}{UnusedCondition}, $Rules{$key}{UnusedValue} );
            }
            $UnusedResult{$key} = $unused;
        }
    }

    # unmount the doamin
    system("fusermount -u $Conf{guestmount_dir}");

    my $result = `cat /proc/mounts | grep $Conf{guestmount_dir}`;
    if ($result) {
        print "$Conf{guestmount_dir} is still mounted. The agent will exit.\n";
        return(\%UnusedResult);
    }

    return(\%UnusedResult);
}
##############################################################################
sub HypervisorCheck {
    my $domain = shift;
    my $unused = "false";
    my %UnusedResult = ();
    for my $key (keys %Rules) {
        if ( $Rules{$key}{Type} eq "Hypervisor" ) {
            $unused = RunCommand($domain, $Rules{$key}{Type}, $Rules{$key}{Command}, $Rules{$key}{UnusedCondition}, $Rules{$key}{UnusedValue} );
            $UnusedResult{$key} = $unused;
        }
    }
    return(\%UnusedResult);
}
##############################################################################
sub RunCommand {
    my $domain           = shift;
    my $type             = shift;
    my $command          = shift;
    my $unused_condition = shift;
    my $unused_value     = shift;
    my $unused_result    = "false";

    print "DEBUG: domain = $domain : type = $type : command = $command : cond = $unused_condition : value = $unused_value\n" if ($debug);
    my $result = `$command $domain`;
    chomp($result);
    print "DEBUG: Command_Result = $result\n" if ($debug);

    if ( $unused_condition eq "LessThan" ) {
        if ( $result < $unused_value ) {
            $unused_result = "true";
        }
    }
    elsif ( $unused_condition eq "GreaterThan" ) {
        if ( $result > $unused_value ) {
            $unused_result = "true";
        }
    }
    elsif ( $unused_condition eq "StringMatch" ) {
        if ( $result eq "$unused_value" ) {
            $unused_result = "true";
        }
    }
    return ($unused_result);
}
##############################################################################
sub RunFunction {
    my $domain           = shift;
    my $type             = shift;
    my $function         = shift;
    my $file_name        = shift;
    my $unused_condition = shift;
    my $unused_value     = shift;
    my $unused_result    = "false";

    print "DEBUG: domain = $domain : type = $type : function = $function : file = $file_name : cond = $unused_condition : value = $unused_value\n" if ($debug);

    ###################################################
    # If Function is FileModTime - if the file is older

    if ( $function eq "FileModTime" ) {
        my $GuestMountedFile = "$Conf{guestmount_dir}"."$file_name";
        if ( -f $GuestMountedFile ) {
            my $file_mod_time = `stat -c %Y $GuestMountedFile`;
            chomp($file_mod_time);
            if ( $unused_condition eq "DaysOlderThan" ) {
                if ( $file_mod_time < ($current_time - ($unused_value * 86400)) ) {
                    $unused_result = "true";
                }
            }
        }
    }
    return ($unused_result);

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
