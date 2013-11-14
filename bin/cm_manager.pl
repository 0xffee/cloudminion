#!/usr/bin/perl

use strict;
use DBI;
use Getopt::Long;

my $base_dir  = "/x/itools/cloud_minion";
my $conf_file = "${base_dir}/conf/cm.cfg";
my $conf_ref = get_conf();
my %Conf = %$conf_ref;

my ($full_run, $list, $set_to_expire, $sync, $delete, $shutdown, $send_reminder);
my ($days_to_expire, $hostname_match, $defined_date, $vm_state);
my ($noop, $debug_email, $help);

GetOptions( 'list|l=s'         => \$list,
            'sync|s'           => \$sync,
            'full-run'         => \$full_run,
            'shutdown'         => \$shutdown,
            'set-expired'      => \$set_to_expire,
            'send-reminder'    => \$send_reminder,
            'days-to-expire=s' => \$days_to_expire,
            'hostname-match=s' => \$hostname_match,
            'debug-email=s'    => \$debug_email,
            'noop'             => \$noop,
            'delete|d'         => \$delete,
            'date=s'           => \$defined_date,
            'state=s'          => \$vm_state,
            'help|h'           => \$help,
);

####################################################################
if ( $full_run ) {
    print "Running full run (sync, set-to-expire, send-reminder, shutdown, delete)\n";

    Sync();
    SetToExpire();
    ShutDownVMs();
    DeleteVMs();
    SendReminder();

}
elsif ( $list =~ m/expired/ ) {
    my $LifeTimeVMs_ref = GetLifeTimeVMs("expired");
    my %LifeTimeVMs = %$LifeTimeVMs_ref;
    if ($list =~ m/expired-by-email/ ) {
        my $UserVMs_ref = GetUserVMs(\%LifeTimeVMs);
        my %UserVMs = %$UserVMs_ref;
        for my $email (keys %UserVMs ) {
            print "$email : $UserVMs{$email}{vms}\n";
        } 
    }
    else {
        print "\nShowing expired VMs\n";
        print "--------------------------------------------------------------------------------\n";
        print "UUID              : hostname  : UserName : ProjectName : UserEmail : ExpirationDate\n";
        for my $uuid (keys %LifeTimeVMs ) {
            print "$uuid\t$LifeTimeVMs{$uuid}{hostname}\t$LifeTimeVMs{$uuid}{user_id}\t$LifeTimeVMs{$uuid}{project_name}\t$LifeTimeVMs{$uuid}{user_email}\t$LifeTimeVMs{$uuid}{expiration_date}\n";
        }
    }
}
elsif ( $list =~ /unused/ ) {
   my $LifeTimeVMs_ref = GetLifeTimeVMs("unused");
   my %LifeTimeVMs = %$LifeTimeVMs_ref;
   if ($list =~ m/unused-by-email/ ) {
        my $UserVMs_ref = GetUserVMs(\%LifeTimeVMs);
        my %UserVMs = %$UserVMs_ref;
        for my $email (keys %UserVMs ) {
            print "$email : $UserVMs{$email}{vms}\n";
        }
   }
   else {
      for my $uuid (keys %LifeTimeVMs) {
          print "$uuid\t$LifeTimeVMs{$uuid}{hostname}\t$LifeTimeVMs{$uuid}{user_id}\t$LifeTimeVMs{$uuid}{project_name}\t$LifeTimeVMs{$uuid}{user_email}\n";
      }
   }
}
elsif ( $list =~ /to-be-shutdown/ ) {
    my $LifeTimeVMs_ref = GetLifeTimeVMs("expired");
    my %LifeTimeVMs = %$LifeTimeVMs_ref;
    for my $uuid (keys %LifeTimeVMs) {
        print "$uuid : $LifeTimeVMs{$uuid}{hostname} : $LifeTimeVMs{$uuid}{user_id} : $LifeTimeVMs{$uuid}{project_name} : $LifeTimeVMs{$uuid}{user_email}\n";
    }
}
elsif ( $list =~ /to-be-deleted/ ) {
    my $LifeTimeVMs_ref = GetLifeTimeVMs("shutdown");
    my %LifeTimeVMs = %$LifeTimeVMs_ref;
    for my $uuid (keys %LifeTimeVMs) {
        print "$uuid : $LifeTimeVMs{$uuid}{hostname} : $LifeTimeVMs{$uuid}{user_id} : $LifeTimeVMs{$uuid}{project_name} : $LifeTimeVMs{$uuid}{user_email}\n";
    }
}
elsif ( $list =~ /reminder-shutdown/ ) {
    my $LifeTimeVMs_ref = GetLifeTimeVMs("reminder-shutdown");
    my %LifeTimeVMs = %$LifeTimeVMs_ref;
    for my $uuid (keys %LifeTimeVMs) {
        print "$uuid : $LifeTimeVMs{$uuid}{hostname} : $LifeTimeVMs{$uuid}{user_id} : $LifeTimeVMs{$uuid}{project_name} : $LifeTimeVMs{$uuid}{user_email}\n";
    }
}
elsif ( $list =~ /reminder-delete/ ) {
    my $LifeTimeVMs_ref = GetLifeTimeVMs("reminder-delete");
    my %LifeTimeVMs = %$LifeTimeVMs_ref;
    for my $uuid (keys %LifeTimeVMs) {
        print "$uuid : $LifeTimeVMs{$uuid}{hostname} : $LifeTimeVMs{$uuid}{user_id} : $LifeTimeVMs{$uuid}{project_name} : $LifeTimeVMs{$uuid}{user_email}\n";
    }
}

####################################################
elsif ( $set_to_expire ) {
   &SetToExpire;
}
elsif ( $sync ) {
   &Sync;
}
elsif ( $delete ) {
   &DeleteVMs;
}
elsif ( $shutdown ) {
   if ( ! $defined_date ) {
      $defined_date = `date +%Y-%m-%d`;
      chomp($defined_date);
   }
   print "Shutting down VMs with expiration date older than $defined_date\n";
   &ShutDownVMs; 
   
}
elsif ( $send_reminder ) {
   &SendReminder;
}
else {
   help();
}
############################################################
############################################################
sub Sync {
    print "\nUpdating records from nova and keystone . . . . \n";
    print "----------------------------------------------------------------------------------------\n";
    my $ActiveVmsFromNova_ref     = GetActiveVMs("nova");
    my %ActiveVmsFromNova         = %$ActiveVmsFromNova_ref;
    my $ActiveVmsFromLifetime_ref = GetActiveVMs("lifetime");
    my %ActiveVmsFromLifetime     = %$ActiveVmsFromLifetime_ref;
    my %UUIDsToUpdate = ();

   print "====  Updating deleted uuids =====\n";
   for my $lifetime_uuid ( keys %ActiveVmsFromLifetime ) {
       my $uuid_is_deleted = 1;
       for my $nova_uuid ( keys %ActiveVmsFromNova ) {
            if ( $nova_uuid eq $lifetime_uuid ) {
                $uuid_is_deleted = 0;
                next;
            }
        }
        if ( $uuid_is_deleted == 1 ) {
            $UUIDsToUpdate{$lifetime_uuid} = 1;
        }
    }
    if ( keys %UUIDsToUpdate > 0 ) {
       UpdateUuids("deleted",\%UUIDsToUpdate);
   }
   #####################################################################
   print "====  Updating missing records =====\n";
   my $ActiveVMs_ref = GetLifeTimeVMs("active");
   my %ActiveVMs = %$ActiveVMs_ref;
   my %UUIDsToUpdate = ();

   for my $uuid (keys %ActiveVMs) {
       #check for missing user_id
       if ( ! $ActiveVMs{$uuid}{user_id} ) {
             if ( $ActiveVmsFromNova{$uuid}{user_id} ) {
                $UUIDsToUpdate{$uuid} = { user_id => $ActiveVmsFromNova{$uuid}{user_id} };
             }
       }

       #check for missing hostame
       if ( ! $ActiveVMs{$uuid}{hostname} ) {
             if ( $ActiveVmsFromNova{$uuid}{hostname} ) {
                $UUIDsToUpdate{$uuid} = { hostname => $ActiveVmsFromNova{$uuid}{hostname} };
             }
             elsif ( $ActiveVmsFromNova{$uuid}{display_name} ) {
                $UUIDsToUpdate{$uuid} = { hostname => $ActiveVmsFromNova{$uuid}{display_name} };
             }
       }

       #check for missing project_name
       if ( ! $ActiveVMs{$uuid}{project_name} ) {
             if ( $ActiveVmsFromNova{$uuid}{project_name} ) {
                $UUIDsToUpdate{$uuid} = { project_name => $ActiveVmsFromNova{$uuid}{project_name} };
             }
       }
       #check for missing project_id
       if ( ! $ActiveVMs{$uuid}{project_id} ) {
             if ( $ActiveVmsFromNova{$uuid}{project_id} ) {
                $UUIDsToUpdate{$uuid} = { project_id => $ActiveVmsFromNova{$uuid}{project_id} };
             }
       }

   }

   #
   #  TODO : the hash needs to be populated at the end - otherwise the last is overwriting it
   #
   if ( keys %UUIDsToUpdate > 0 ) {
       UpdateUuids("records",\%UUIDsToUpdate);
   }


   ###################################################################
   # Update email after updating user_id
   #print "====  Updating missing records =====\n";
   my $ActiveVMs_ref = GetLifeTimeVMs("active");
   my %ActiveVMs = %$ActiveVMs_ref;
   my %UUIDsToUpdate = ();

   #Pushed all known emails into a hash,
   my %UserInfo = ();
   for my $uuid (keys %ActiveVMs) {
      my $user = $ActiveVMs{$uuid}{user_id};
      if ( ! $UserInfo{$user} ) {
          if ( $ActiveVMs{$uuid}{user_email} ) {
              $UserInfo{$user} = $ActiveVMs{$uuid}{user_email};
          }
      }
   }
   for my $uuid (keys %ActiveVMs) {
       if ( ! $ActiveVMs{$uuid}{user_email} ) {
            # Check if the email address is already in the hash
            my $user = $ActiveVMs{$uuid}{user_id};
            if ( ! $UserInfo{$user} ) {
                $UserInfo{$user} = GetEmailAddress($user);
            }
            $UUIDsToUpdate{$uuid} = { email => $UserInfo{$user} };
       }
   }
   ###################################################################
   #
   #  TODO : the hash needs to be populated at the end - otherwise the last is overwriting it
   #
   if ( keys %UUIDsToUpdate > 0 ) {
       UpdateUuids("records",\%UUIDsToUpdate);
   }
}
##############################################################
sub SetToExpire {
   my $option;
   my $option_value = "";
   my $description;
   if ( ! $days_to_expire ) {
       $days_to_expire = $Conf{days_to_expire};
   }
   if ( $hostname_match ) {
      $description = "all VMs with hostname matching $hostname_match";
      $option = "match";
      $option_value = "$hostname_match";
   }
   else {
      $description = "all VMs marked as unused";
      $option = "unused";
   }

   print "Seting $description to expire in $days_to_expire\n";
   SetVMsToExpire($days_to_expire,$option,$option_value);
}
############################################################
sub GetLifeTimeVMs {
    my $what = shift;
    my $what_value = shift;
    my %LifeTimeVMs = ();
    my $where_condition = "";
    my @ExcludeProjects = split/,/,$Conf{exclude_projects};
    my %ExcludeProjects = map { $_ => 1 } @ExcludeProjects;

    my $sql;

    my $dbh = DBI->connect("DBI:mysql:database=$Conf{lifetime_db};host=$Conf{db_host}", "$Conf{readonly_user}", "$Conf{readonly_password}",
               {'RaiseError' => 1 });
    #if ( $defined_date ) {
    #     $where_condition = "and expiration_date <= '$defined_date'";
    #}
    #elsif ( $vm_state ) {
    #    $where_condition = "and state = '$vm_state'";
    #}

    if ($what eq "active" ) {
        $where_condition = qq[where deleted = 0];
    }
    elsif ($what eq "expired" ) {
        $where_condition = qq[where deleted = 0 and expiration_date != '0000-00-00' and expiration_date <= CURDATE()];
    }
    elsif ($what eq "unused" )  {
        $where_condition = qq[where deleted = 0 and unused = 'true' and expiration_date is null and state != 'not_in_nova'];    
    }
    elsif ($what eq "shutdown" ) {
        $where_condition = qq[where deleted = 0 and state = 'shutdown' and expiration_date <= DATE_SUB(CURDATE(), interval 7 day)];
    }
    elsif ($what eq "reminder-shutdown" ) {
        $where_condition = qq[where deleted = 0 and expiration_date = DATE_ADD(CURDATE(), interval 2 day)];
    }
    elsif ($what eq "reminder-delete" ) {
        $where_condition = qq[where deleted = 0 and state = 'shutdown' and expiration_date = DATE_SUB(CURDATE(), interval 5 day)];
    }
    elsif ($what eq "match" ) {
        $where_condition = qq[where deleted = 0 and expiration_date is null and state != 'not_in_nova' and hostname like '%$what_value%'];
    }

    $sql = qq[select uuid,hostname,compute_host,user_id,project_id,project_name,user_email,expiration_date from $Conf{lifetime_db}.instance_lifetimes $where_condition];

    my $sth = $dbh->prepare($sql) or die "Couldn't prepare query";
    $sth->execute();
    $sth->rows;
    my $row_number = $sth->rows;
    while (my @rows = $sth->fetchrow_array()) {
         my $uuid            = $rows[0];
         my $hostname        = $rows[1];
         my $compute_host    = $rows[2];
         my $user_id         = $rows[3];
         my $project_id      = $rows[4];
         my $project_name    = $rows[5];
         my $user_email      = $rows[6];
         my $expiration_date = $rows[7];
         next if (exists($ExcludeProjects{$project_name}));
         $LifeTimeVMs{$uuid} = { hostname        => "$hostname", 
                                 compute_host    => "$compute_host",
                                 user_id         => "$user_id", 
                                 project_id      => "$project_id",
                                 project_name    => "$project_name",
                                 user_email      => "$user_email",
                                 expiration_date => "$expiration_date", 
         };
    }
    $sth->finish();
    $dbh->disconnect();

    return(\%LifeTimeVMs);
}
############################################################
sub GetActiveVMs {
    my $where = shift;
    my %Records = ();
    my $sql;

    if ( $where eq "nova" ) {
        $sql = qq[select ni.uuid,ni.hostname,ni.user_id,ni.project_id,kt.name,ni.display_name from $Conf{nova_db}.instances ni LEFT JOIN $Conf{keystone_db}.project kt on ni.project_id = kt.id where ni.deleted = 0];
    }
    elsif ( $where eq "lifetime" ) {
        $sql = "select uuid,hostname,user_id,project_id,project_name from $Conf{lifetime_db}.instance_lifetimes where deleted = 0";
    }
    my $dbh = DBI->connect("DBI:mysql:database=$Conf{lifetime_db};host=$Conf{db_host}", "$Conf{readonly_user}", "$Conf{readonly_password}",
               {'RaiseError' => 1 });
    my $sth = $dbh->prepare($sql) or die "Couldn't prepare query";
    $sth->execute();
    $sth->rows;
    while (my @rows = $sth->fetchrow_array()) {
         my $uuid = $rows[0];
         my $hostname = $rows[1];
         my $user_id = $rows[2];
         my $project_id = $rows[3];
         my $project_name = $rows[4];
         my $display_name = $rows[5];
         $Records{$uuid} = { hostname => $hostname, user_id => $user_id, project_id => $project_id, project_name => $project_name, display_name => $display_name };
    }
    $sth->finish();

    $dbh->disconnect();
    return(\%Records);
}

############################################################
sub UpdateUuids {
   my $what = shift;
   my $UUIDsToUpdate_ref = shift;
   my %UUIDsToUpdate = %$UUIDsToUpdate_ref;

   my $dbh = DBI->connect("DBI:mysql:database=$Conf{lifetime_db};host=$Conf{db_host}", "$Conf{lifetime_user}", "$Conf{lifetime_password}",
               {'RaiseError' => 1 });

   if ($what eq "records" ) {
       #print "Updating email ......\n";
       for my $uuid (keys %UUIDsToUpdate) {
           #print "Updating $uuid with email: $UUIDsToUpdate{$uuid}\n";
           if ( $UUIDsToUpdate{$uuid}{user_id} ) {
               print "Updating $uuid with user_id: $UUIDsToUpdate{$uuid}{user_id}\n";
               my $sql = qq[update instance_lifetimes set user_id = '$UUIDsToUpdate{$uuid}{user_id}' where uuid = '$uuid'];
               my $sth = $dbh->prepare($sql) or die "Couldn't prepare query";
               $sth->execute();
               $sth->finish();
           }
           if ( $UUIDsToUpdate{$uuid}{email} ) {
               print "Updating $uuid with email: $UUIDsToUpdate{$uuid}{email}\n";
               my $sql = qq[update instance_lifetimes set user_email = '$UUIDsToUpdate{$uuid}{email}' where uuid = '$uuid'];
               my $sth = $dbh->prepare($sql) or die "Couldn't prepare query";
               $sth->execute(); 
               $sth->finish();
           }
           if ( $UUIDsToUpdate{$uuid}{hostname} ) {
               print "Updating $uuid with hostname: $UUIDsToUpdate{$uuid}{hostname}\n";
               my $sql = qq[update instance_lifetimes set hostname = '$UUIDsToUpdate{$uuid}{hostname}' where uuid = '$uuid'];
               my $sth = $dbh->prepare($sql) or die "Couldn't prepare query";
               $sth->execute();
               $sth->finish();
           }
           if ( $UUIDsToUpdate{$uuid}{project_name} ) {
               print "Updating $uuid with project_name: $UUIDsToUpdate{$uuid}{project_name}\n";
               my $sql = qq[update instance_lifetimes set project_name = '$UUIDsToUpdate{$uuid}{project_name}' where uuid = '$uuid'];
               my $sth = $dbh->prepare($sql) or die "Couldn't prepare query";
               $sth->execute();
               $sth->finish();
           }
           if ( $UUIDsToUpdate{$uuid}{project_id} ) {
               print "Updating $uuid with project_id: $UUIDsToUpdate{$uuid}{project_id}\n";
               my $sql = qq[update instance_lifetimes set project_id = '$UUIDsToUpdate{$uuid}{project_id}' where uuid = '$uuid'];
               my $sth = $dbh->prepare($sql) or die "Couldn't prepare query";
               $sth->execute();
               $sth->finish();
           }

       }
   }
   elsif ($what eq "expiration_date") {
         for my $uuid (keys %UUIDsToUpdate) {
              my $sql = qq[update instance_lifetimes set expiration_date = DATE_ADD(CURDATE(), interval $days_to_expire day) where uuid = '$uuid'];
              my $sth = $dbh->prepare($sql) or die "Couldn't prepare query";
              $sth->execute();
              $sth->finish();
              logger("Updating expiration date: uuid: $uuid  Days to expire: $days_to_expire");
         }

   }
   elsif ($what eq "shutdown" ) {
       for my $uuid (keys %UUIDsToUpdate) {
           my $sql = qq[update instance_lifetimes set state = 'shutdown' where uuid = '$uuid'];
           my $sth = $dbh->prepare($sql) or die "Couldn't prepare query";
           $sth->execute();
           $sth->finish();
       }
   }
   elsif ($what eq "deleted" ) {
       for my $uuid (keys %UUIDsToUpdate) {
           print "Updating $uuid with deleted = 1\n";
           my $sql = qq[update instance_lifetimes set deleted = 1 and state = 'deleted' where uuid = '$uuid'];
           my $sth = $dbh->prepare($sql) or die "Couldn't prepare query";
           $sth->execute();
           $sth->finish();
       }
   }

   $dbh->disconnect();

}
############################################################
sub SetVMsToExpire {
   my $days_to_expire = shift;
   my $option = shift;
   my $option_value = shift;
   my %SelectedVMs = ();
   my %UserEmail_VMs_List = ();

   if ( $option eq "match" ) {
      print "Setting to expire VMs matching $option_value\n";
      my $SelectedVMs_ref = GetLifeTimeVMs($option,$option_value);
      %SelectedVMs = %$SelectedVMs_ref;
   }
   elsif ( $option eq "unused" ) {
      print "Setting to expire VMs marked as unused\n";
      my $SelectedVMs_ref = GetLifeTimeVMs("unused");
      %SelectedVMs = %$SelectedVMs_ref;
   }

   if ( keys %SelectedVMs > 0 ) {
       my $UserEmail_VMs_List_ref = GetUserVMs(\%SelectedVMs);
       %UserEmail_VMs_List = %$UserEmail_VMs_List_ref;

       # Updating the DB
       if (!$noop) {
          UpdateUuids("expiration_date",\%SelectedVMs);
       }
       else {
          print "NOT UPDATING\n";
       }
 
       #Sending notification
       my $expiration_date = GetExpirationDate($days_to_expire);
       SendNotification(\%UserEmail_VMs_List, "expiration", $expiration_date);

   }
}
############################################################
sub SendReminder {

    my $days_to_expire = 2;  # TODO - make this configurable

    #To be shutdown
    my $SelectedVMs_ref = GetLifeTimeVMs("reminder-shutdown");
    my %SelectedVMs = %$SelectedVMs_ref;

    if ( keys %SelectedVMs > 0 ) {     
        my $UserEmail_VMs_List_ref = GetUserVMs(\%SelectedVMs);
        my %UserEmail_VMs_List = %$UserEmail_VMs_List_ref;

        my $expiration_date = GetExpirationDate($days_to_expire);
        SendNotification(\%UserEmail_VMs_List, "reminder-shutdown", $expiration_date);
    }

    #To be deleted
    my $SelectedVMs_ref = GetLifeTimeVMs("reminder-delete");
    my %SelectedVMs = %$SelectedVMs_ref;

    if ( keys %SelectedVMs > 0 ) {
        my $UserEmail_VMs_List_ref = GetUserVMs(\%SelectedVMs);
        my %UserEmail_VMs_List = %$UserEmail_VMs_List_ref;

        my $expiration_date = GetExpirationDate($days_to_expire);
        SendNotification(\%UserEmail_VMs_List, "reminder-delete", $expiration_date);
    }

}
############################################################
sub SendNotification {
    my $List_ref          = shift;
    my $notification_type = shift;
    my $expiration_date   = shift;
    my $email_file = "/var/tmp/email_file.txt";
    my $subject = "$Conf{email_subject_expiration}";
    my %List = %$List_ref;

    if ($notification_type =~ m/reminder/ ) {
       $subject = "Reminder: $subject";
    }

    my $EmailTemplate = "${base_dir}/email_templates/${notification_type}.tmpl";

    for my $email (keys %List ) {
        my $user_vms = $List{$email}{vms};
        my $project_id = $List{$email}{project_id};
        $user_vms =~ s/,/\n/g;

        my @EmailTemplate = `cat $EmailTemplate`;

        my $no_email_users_message = "";
        if ( "$email" eq "$Conf{default_group_email}" ) {
             $no_email_users_message = $Conf{no_email_users_message};
        }

        open(EMAIL_FILE, ">$email_file");
        foreach my $line (@EmailTemplate) {
            chomp($line);
            if ($line =~ m/__VM_LIST__/ ) {
                $line =~ s/__VM_LIST__/$user_vms/;
            }
            elsif ($line =~ m/__TID__/ ) {
                my $tid = "";
                $line =~ s/__TID__/$project_id/;
            }
            elsif ($line =~ m/__EXPIRATION_DATE__/ ) {
                $line =~ s/__EXPIRATION_DATE__/$expiration_date/;
            }
            elsif ($line =~ m/__NO_EMAIL_USERS_MESSAGE__/ ) {
                $line =~ s/__NO_EMAIL_USERS_MESSAGE__/$no_email_users_message/;
            }

            print EMAIL_FILE "$line\n";
        }
        close(EMAIL_FILE);

        #Send email
        $email = $debug_email if ($debug_email);
        system("${base_dir}/bin/emailer.pl -t $email -S '$subject' -f $email_file");
        $user_vms =~ s/\n/,/g;
        logger("Emailing: $email VMS: $user_vms Project_ID: $project_id");
    }

}
############################################################
sub ShutDownVMs {
    my $SelectedVMs_ref = GetLifeTimeVMs("expired");
    my %SelectedVMs     = %$SelectedVMs_ref;

    if ( keys %SelectedVMs > 0 ) {
       my $UserEmail_VMs_List_ref = GetUserVMs(\%SelectedVMs);
       my %UserEmail_VMs_List = %$UserEmail_VMs_List_ref;

       # Updating the DB
       if (!$noop) {
           UpdateUuids("shutdown",\%SelectedVMs);
           for my $uuid (keys %SelectedVMs) {
               print "Shutting down: $uuid -> $SelectedVMs{$uuid}{hostname}\n";
               logger("Shutting down $uuid -> $SelectedVMs{$uuid}{hostname}");
               my $result = `${base_dir}/bin/run_os_cmd.sh nova stop $uuid`;
               if ( $result ne "" ) {
                   print "Result: $result\n";
                   logger("Error: $uuid - $result");
               }
           }
       }
       else {
          print "NOT UPDATING\n";
       }

       #Sending notification
       my $expiration_date = GetExpirationDate($days_to_expire);
       SendNotification(\%UserEmail_VMs_List, "shutdown", $expiration_date);
   }
}
############################################################
sub DeleteVMs {
    my $SelectedVMs_ref = GetLifeTimeVMs("shutdown");
    my %SelectedVMs     = %$SelectedVMs_ref;

    if ( keys %SelectedVMs > 0 ) {
       my $UserEmail_VMs_List_ref = GetUserVMs(\%SelectedVMs);
       my %UserEmail_VMs_List     = %$UserEmail_VMs_List_ref;

       # Updating the DB
       if (!$noop) {
           UpdateUuids("deleted",\%SelectedVMs);
           for my $uuid (keys %SelectedVMs) {
               print "Deleting: $uuid -> $SelectedVMs{$uuid}{hostname}\n";
               logger("Deleting: $uuid -> $SelectedVMs{$uuid}{hostname}");
               my $result = `${base_dir}/bin/run_os_cmd.sh nova delete $uuid`;
               if ( $result ne "" ) {
                   print "Result: $result\n";
                   logger("Error: $uuid - $result");
               }
           }
       }
       else {
          print "NOT UPDATING\n";
       }

       #Sending notification
       #my $expiration_date = GetExpirationDate($days_to_expire);
       SendNotification(\%UserEmail_VMs_List, "deleted" );
   }


}
############################################################
sub GetEmailAddress {
   my $username = shift;
   my $email = "n/a";
   my $result = `$Conf{ldap_script} $username | grep '\@'`;
   chomp($result);
   if ($result ne "" ) {
      $email = $result;
   }
   return($email);
}

############################################################
sub GetUserVMs {
   my $LifeTimeVMs_ref = shift;
   my %LifeTimeVMs = %$LifeTimeVMs_ref;
   my %UserEmails = ();
   my %Email_VMs_List = ();

   # Get all email addresses for all unused VMs
   for my $uuid (keys %LifeTimeVMs) {
       if ( ! $UserEmails{$LifeTimeVMs{$uuid}{user_email}} ) {
            $UserEmails{$LifeTimeVMs{$uuid}{user_email}} = 1;
       }
   }
   # List the emails and the VMs
   for my $email ( keys %UserEmails ) {
      my $user_unused_vms;
      my $project_id;
      for my $uuid (keys %LifeTimeVMs) {
          if ( $email eq $LifeTimeVMs{$uuid}{user_email} ) {
               $user_unused_vms = "$user_unused_vms,$LifeTimeVMs{$uuid}{hostname}";
               $project_id = "$LifeTimeVMs{$uuid}{project_id}";
          }
      }
      $user_unused_vms =~ s/^,//g;
      if ($email eq "n/a") {
           $email      = $Conf{default_group_email};
           $project_id = $Conf{admin_user_tid};
      }
      if ( $Conf{email_domain_replace} ) {
          $email =~ s/@.*/\@$Conf{email_domain_replace}/;
      }
      $Email_VMs_List{$email} = { vms => $user_unused_vms, project_id => $project_id };
   }
   return(\%Email_VMs_List);

}
############################################################
sub GetExpirationDate {
    my $days_to_expire = shift;
    my $time = time();
    my $future_time = $time + ($days_to_expire * 24 * 60 *60);  
    my ($fsec, $fmin, $fhour, $fday, $fmonth, $fyear) = localtime($future_time);
    $fyear += 1900;
    $fmonth += 1;
    my $expiration_date = "$fmonth/$fday/$fyear";
    return $expiration_date;
}
############################################################
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
###########################################################
sub logger {
    my $message = shift;
    my $date = `date`;
    chomp($date);
    open(LOG, ">>$Conf{cloud_minion_log}");
    print LOG "$date: $message\n";
    close(LOG);
}
###########################################################
sub help {
   print "Usage: $0 --list|--delete|--sync\n";
   print "\t--list\n";
   print "\t		<unused>         List unused VMs\n";
   print "\t		<to-be-shutdown> List VMs that need to be shutdown\n";
   print "\t		<to-be-deleted>  List VMs that need to be shutdown\n";
   print "\t		<reminder-shutdown>\n";
   print "\t		<reminder-delete>\n";
   print "\t--full-run		Runs: sync,set-expired,shutdown,delete,send-reminder\n";
   print "\t--set-expired	Sets VMs marked as unused to expire\n";
   print "\t--delete    	Deletes the VMs scheduled to deleted today\n";
   print "\t--sync      	Syncs lifetime with nova and keystone, deleted uuids, missing records, etc\n";
   print "\t--shutdown		Shuts down VMs scheduled to be deleted. Optional: Use --date <yyyy-mm-dd> to specify a date\n";
   print "\t--send-reminder	Send reminder for VMs to be shutdown or deleted\n";
   print "\t--noop		Does not update the DB\n";
   print "\t--debug-email	Send emails to the debug-email address only\n";
}
