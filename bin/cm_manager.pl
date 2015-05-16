#!/usr/bin/perl

use strict;
use DBI;
use Getopt::Long;
use FindBin;
use Data::UUID;

my $bin_dir       = $FindBin::Bin;
my $templates_dir = "$FindBin::Bin/../email_templates";
my $global_conf_file     = "$FindBin::Bin/../conf/cm-global.cfg";
my $conf_ref = get_conf($global_conf_file);
my %Conf = %$conf_ref;

my ($full_run, $report, $list, $set_to_expire, $sync, $delete, $shutdown, $send_reminder);
my ($days_to_expire, $hostname_match, $defined_date, $vm_state, $uuid2sync,$user2sync);
my ($batch, $vpc, $cell, $list_all_users, $noop, $noemail, $force, $debug, $debug_email, $help, $conf_file);
my ($report_format);

GetOptions( 'report=s'          => \$report,
            'sync|s'            => \$sync,
            'full-run'          => \$full_run,
            'shutdown'          => \$shutdown,
            'set-expired'       => \$set_to_expire,
            'send-reminder=s'   => \$send_reminder,
            'days-to-expire=s'  => \$days_to_expire,
            'hostname-match=s'  => \$hostname_match,
            'uuid=s'            => \$uuid2sync,
            'user=s'            => \$user2sync,
            'vpc=s'             => \$vpc,
            'cell=s'            => \$cell,
            'batch=s'           => \$batch,
            'debug'             => \$debug,
            'debug-email=s'     => \$debug_email,
            'noop'              => \$noop,
            'noemail'           => \$noemail,
            'force'             => \$force,
            'delete|d'          => \$delete,
            'date=s'            => \$defined_date,
            'state=s'           => \$vm_state,
            'list-all-users'    => \$list_all_users,
            'format=s'          => \$report_format,
            'help|h'            => \$help,
);

my @Cells = ();
my @AvailableCells = ();

@Cells = split/,/,$Conf{cells};
for my $defined_cell ( @Cells ) {
   $defined_cell = trim($defined_cell);
   if ($cell) {
        if ( $defined_cell eq $cell ) {
            push @AvailableCells, $defined_cell;
        }
        elsif ( $cell eq "all" ) {
            push @AvailableCells, $defined_cell;
        }
   }
   else {
       push @AvailableCells, $defined_cell;
   }
}
my $cell_number = @AvailableCells;
if ( $cell_number == 0 ) {
    print "Cell: $cell is not defined in cells in $global_conf_file\n";
    exit;
}
for my $avail_cell (@AvailableCells) { 
    my $cell_conf_file = "$FindBin::Bin/../conf/${avail_cell}_cm.cfg";
    if ( ! -f $cell_conf_file) {
        print "Missing cell config file: $cell_conf_file\n";
        exit;
    }
}

#######################################################################
#######################################################################

my %Reports = ();
$Reports{unused}           = { name => 'Set to expire', order => '1' };
$Reports{expired}          = { name => 'To be shutdown', order => '2' };
$Reports{shutdown}          = { name => 'To be deleted', order => '3' };
$Reports{shutdown_reminder} = { name => 'Reminder to be shutdown', order => '4' };
$Reports{delete_reminder}   = { name => 'Reminder to be deleted', order => '5' };

my %ColumnNames = ();
$ColumnNames{uuid}            = { colname => 'UUID', order => '1' };
$ColumnNames{hostname}        = { colname => 'Hostname', order => '2' };
$ColumnNames{user_name}       = { colname => 'User', order => '3' };
$ColumnNames{user_email}      = { colname => 'UserEmail', order => '4' };
$ColumnNames{project_name}    = { colname => 'Project', order => '5' };
$ColumnNames{memory_mb}       = { colname => 'Memory MB', order => '6' };
$ColumnNames{vcpus}           = { colname => 'CPU', order => '7' };
$ColumnNames{disk_gb}         = { colname => 'Disk GB', order => '8' };
$ColumnNames{expiration_date} = { colname => 'Expiration Date', order => '9' };
$ColumnNames{vm_state}        = { colname => 'State', order => '10' };

if ( ! $defined_date ) {
    $defined_date = `date +%Y-%m-%d`;
    chomp($defined_date);
}

$vpc = $Conf{vpc} if ( $Conf{vpc} );
#print "Using cell: $cell\n";
#print "Applying filter vpc = $vpc \n\n" if  ( $vpc );

####################################################################
my $cm_dbh = DBI->connect("DBI:mysql:database=$Conf{cm_global_db};host=$Conf{cm_db_host};port=$Conf{cm_db_port}",
                        "$Conf{cm_user}", "$Conf{cm_password}",
                        {'RaiseError' => 1 });

####################################################################
if ( $full_run ) {
    print "Running full run (sync, set-to-expire, send-reminder, shutdown, delete)\n";

    #Sync();
    #SetToExpire();
    #ShutDownVMs();
    #DeleteVMs();
    #SendReminder("shutdown_reminder");
    #SendReminder("delete_reminder");
}
elsif ( $report ) {
    for my $cell (@AvailableCells) {
        Report($cell); 
    }
}
elsif ( $set_to_expire ) {
        SetToExpire(); 
}
elsif ( $sync ) {
    for my $cell (@AvailableCells) {
       Sync($cell); 
    }
}
elsif ( $delete ) {
    ActionOnVMs("delete"); 
}
elsif ( $shutdown ) {
    ActionOnVMs("shutdown");  
}
elsif ( $send_reminder ) {
   if ( $send_reminder eq "unused" ) {
       SendReminder("unused"); 
   }
   else {
       SendReminder("shutdown_reminder");
       SendReminder("delete_reminder");
   }
}
elsif ( $list_all_users ) {
   print "Listing all users\n";
   print "##################################################\n";
   my $AllGlobalUsers_ref      = GetAllGlobalUsers();
   my %AllGlobalUsers          = %$AllGlobalUsers_ref;
   for my $user_name ( keys %AllGlobalUsers ) {
       print "$AllGlobalUsers{$user_name}{user_uuid}\t$user_name\t$AllGlobalUsers{$user_name}{user_email}\n";
   }

}
else {
   help();
}
############################################################

$cm_dbh->disconnect();

############################################################
sub Sync {
    my $cell = shift;
    if ($batch) {
        print "Error:   --batch cannot be used in combination with --sync or --full-run\n";
        exit;
    }
    print "====================================================\n";
    print " Syncing cell: $cell\n";
    print "====================================================\n";
   
    print "\nRunning Sync ( Sync CloudMinion DB from OpenStack DB) ............... \n";
    my $AllNovaVMs_ref  = GetAllNovaVMs($cell); 
    my %AllNovaVMs      = %$AllNovaVMs_ref;
    my $AllKeystoneProjects_ref = GetAllKeystone($cell, "projects");
    my %AllKeystoneProjects     = %$AllKeystoneProjects_ref;
    my $AllKeystoneUsers_ref    = GetAllKeystone($cell, "users");
    my %AllKeystoneUsers        = %$AllKeystoneUsers_ref;
   
    my $AllGlobalUsers_ref      = GetAllGlobalUsers();  
    my %AllGlobalUsers          = %$AllGlobalUsers_ref;

    my $AllCmVMs_ref    = GetAllCmVMs($cell, "sync"); 
    my %AllCmVMs        = %$AllCmVMs_ref;

    my %UUIDsToDelete = ();
    my %UUIDsToUpdate = ();

    if (! $uuid2sync ) {
        print "\tUpdating deleted uuids ......................\n";
        for my $uuid (keys %AllCmVMs ) {
            if ( ! $AllNovaVMs{$uuid} ) {
                $UUIDsToDelete{$uuid} = 1;
            }
        }
        if ( keys %UUIDsToDelete > 0 ) {
            UpdateUuids($cell, "sync_delete",\%UUIDsToDelete);
        }
    }
    #####################################################################
    print "\tInserting missing records ....................\n";
    for my $uuid (keys %AllNovaVMs ) {
       if ( ! $AllCmVMs{$uuid} ) {
            $UUIDsToUpdate{$uuid} = $AllNovaVMs{$uuid};
        }
    }
    if ( keys %UUIDsToUpdate > 0 ) {
       UpdateUuids($cell, "insert",\%UUIDsToUpdate);
    }

    #####################################################################
    print "\tUpdating missing fields from nova db ..............\n";
    my $ActiveVMs_ref = GetAllCmVMs($cell, "sync");
    my %ActiveVMs = %$ActiveVMs_ref;
    my %UUIDsToUpdate = ();

    for my $uuid (keys %ActiveVMs) {
        next if ( defined $uuid2sync and "$uuid2sync" ne "$uuid");
        next if ( defined $user2sync and "$user2sync" ne "$ActiveVMs{$uuid}{user_name}");
          
        #if ( ! $ActiveVMs{$uuid}{hostname} or ! $ActiveVMs{$uuid}{user_name} ) {
        if ( ! $ActiveVMs{$uuid}{hostname} or ( $ActiveVMs{$uuid}{vm_state} ne $AllNovaVMs{$uuid}{vm_state} ) ) {
            $UUIDsToUpdate{$uuid}{hostname} = $AllNovaVMs{$uuid}{hostname};
            $UUIDsToUpdate{$uuid}{user_id} = $AllNovaVMs{$uuid}{user_id};
            $UUIDsToUpdate{$uuid}{project_id} = $AllNovaVMs{$uuid}{project_id};
            $UUIDsToUpdate{$uuid}{memory_mb} = $AllNovaVMs{$uuid}{memory_mb};
            $UUIDsToUpdate{$uuid}{vcpus} = $AllNovaVMs{$uuid}{vcpus};
            $UUIDsToUpdate{$uuid}{disk_gb} = $AllNovaVMs{$uuid}{disk_gb};
            $UUIDsToUpdate{$uuid}{compute_host} = $AllNovaVMs{$uuid}{compute_host};
            $UUIDsToUpdate{$uuid}{display_name} = $AllNovaVMs{$uuid}{display_name};
            $UUIDsToUpdate{$uuid}{vpc} = $AllNovaVMs{$uuid}{vpc};
            my $user_id    = $AllNovaVMs{$uuid}{user_id};
            my $project_id = $AllNovaVMs{$uuid}{project_id};
            $UUIDsToUpdate{$uuid}{user_name}    = $AllKeystoneUsers{$user_id}{name};
            $UUIDsToUpdate{$uuid}{project_name} = $AllKeystoneProjects{$project_id}{name};
            $UUIDsToUpdate{$uuid}{vm_state} = $AllNovaVMs{$uuid}{vm_state};
        }
    }
    if ( keys %UUIDsToUpdate > 0 ) {
       UpdateUuids($cell, "update",\%UUIDsToUpdate);
    }

# TODO change to update cm_users emails
    #####################################################################
#    print "\tUpdating missing email addresses ....................\n";
    my $ActiveVMs_ref = GetAllCmVMs($cell, "sync");
    my %ActiveVMs = %$ActiveVMs_ref;
    #Push all known emails into a hash,
    my %UserInfo = ();
    for my $uuid (keys %ActiveVMs) {
        my $user = $ActiveVMs{$uuid}{user_name};
        if ( ! $UserInfo{$user} ) {
               $UserInfo{$user} = "-";
        }
    }

    ####################################################################
    print "\tUpdating CM GlobalUsers ...............................\n";
    my %GlobalUsersToUpdate = ();
    for my $user_name (keys %UserInfo ) {
         next if ( defined $user2sync and "$user2sync" ne "$user_name");  
         #print "user: $user_name .... $AllGlobalUsers{$user_name}\n";
         if ( ! $AllGlobalUsers{$user_name} ) {
              my $ug    = Data::UUID->new;
              my $user_uuid = $ug->create_str();
              $user_uuid =~ s/-//g; 
              #print "New: $user_name -> $user_uuid\n"; 
              $GlobalUsersToUpdate{$user_name}{user_uuid} = $user_uuid;
              my $user_email = GetEmailAddress($user_name, "user-email");
              $GlobalUsersToUpdate{$user_name}{user_email} = $user_email;
              my $active_email = 1;
              if ( $user_email eq "n/a" ) {
                 $active_email = 0;
              }
              $GlobalUsersToUpdate{$user_name}{active_email} = $active_email;
              
         }
    }
    if ( keys %GlobalUsersToUpdate > 0 ) {
         UpdateGlobalUsers(\%GlobalUsersToUpdate);
    }

}
##############################################################
sub SetToExpire { 
   my $option;
   my $option_value = "";
   my $description;

   print "\n\nRunning SetToExpire ..................\n";
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

   SetVMsToExpire($days_to_expire,$option,$option_value);
}
############################################################
sub GetAllNovaVMs {
    my $cell = shift;
    my $conf_file   = "$FindBin::Bin/../conf/${cell}_cm.cfg";
    my $conf_ref = get_conf($conf_file);
    my %CellConf = %$conf_ref;

    my $target_db = "nova";
    my %Records = ();
    
    my $tenant_table = "project";
    if ( $CellConf{os_release} eq "Folsom" ) {
        $tenant_table = "tenant";
    }
   # TODO - make nim.key configurable 
    my $where_condition = qq[where ni.deleted = 0 and nim.`key` = 'project_cos'];
    if ($uuid2sync) { 
       $where_condition .= qq[ and ni.uuid = '$uuid2sync'];
    }
    elsif ($user2sync) {
       my $user_id = GetUserID($cell, $user2sync);
       $where_condition .= qq[ and ni.user_id = '$user_id'];
    }
    my $sql = qq[select ni.uuid,ni.hostname,ni.user_id,ni.project_id,ni.memory_mb,ni.vcpus,ni.root_gb + ni.ephemeral_gb,SUBSTRING_INDEX(ni.host, '.', 1),ni.display_name,nim.value,ni.vm_state from $CellConf{nova_db}.instances ni LEFT JOIN $CellConf{nova_db}.instance_metadata nim on ni.uuid = nim.instance_uuid $where_condition];

    print "DBI Conn: database=$CellConf{nova_db} : host=$CellConf{os_nova_db_host} : port=$CellConf{os_nova_db_port} : user=$CellConf{os_user} : password=$CellConf{os_password}\n" if ($debug);
    print "SQL: $sql \n" if ($debug);
    my $os_dbh = DBI->connect("DBI:mysql:database=$CellConf{nova_db};host=$CellConf{os_nova_db_host};port=$CellConf{os_nova_db_port}", "$CellConf{os_user}", "$CellConf{os_password}",
       {'RaiseError' => 1 });
    my $sth = $os_dbh->prepare($sql) or die "Couldn't prepare query";
    $sth->execute();
    $sth->rows;
    while (my @rows = $sth->fetchrow_array()) {
         my $uuid         = $rows[0];
         my $hostname     = $rows[1];
         my $user_id      = $rows[2];
         my $project_id   = $rows[3];
         my $memory_mb    = $rows[4];
         my $vcpus        = $rows[5];
         my $disk_gb      = $rows[6];
         my $compute_host = $rows[7];
         my $display_name = $rows[8];
         my $vpc          = $rows[9];
         my $vm_state     = $rows[10];
         $Records{$uuid} = { hostname     => $hostname,
                             user_id      => $user_id,
                             project_id   => $project_id,
                             memory_mb    => $memory_mb,
                             vcpus        => $vcpus,
                             disk_gb      => $disk_gb,
                             compute_host => $compute_host,
                             display_name => $display_name,
                             vpc          => $vpc,
                             vm_state     => $vm_state,
        };
    }
    $sth->finish();
    $os_dbh->disconnect();
    return(\%Records);
}

############################################################
sub GetAllKeystone {
    my $cell = shift;
    my $what = shift;
    my $conf_file   = "$FindBin::Bin/../conf/${cell}_cm.cfg";
    my $conf_ref = get_conf($conf_file);
    my %CellConf = %$conf_ref;

    my %Records = ();
    my $sql;
    if ( $what eq "projects" ) {
       $sql = qq[select id, name from $CellConf{keystone_db}.project];
    }
    elsif ( $what eq "users" ) {
       $sql = qq[select id,name from $CellConf{keystone_db}.user];
    }
    print "DBI Conn: database=$CellConf{keystone_db} : host=$CellConf{os_keystone_db_host} : port=$CellConf{os_keystone_db_port} : user=$CellConf{os_user} : password=$CellConf{os_password}\n" if ($debug);
    print "SQL: $sql\n" if ($debug);

    my $os_dbh = DBI->connect("DBI:mysql:database=$CellConf{keystone_db};host=$CellConf{os_keystone_db_host};port=$CellConf{os_keystone_db_port}", "$CellConf{os_user}", "$CellConf{os_password}",
       {'RaiseError' => 1 });
    my $sth = $os_dbh->prepare($sql) or die "Couldn't prepare query";
    $sth->execute();
    $sth->rows;
    while (my @rows = $sth->fetchrow_array()) {    
        my $id = $rows[0];
        my $name = $rows[1];
        $Records{$id} = { name => $name };
    }
 
    $sth->finish();
    $os_dbh->disconnect();
    return(\%Records);
}
############################################################
sub GetAllGlobalUsers {
    my %Records = ();
    my $sql = qq[select cm_uid, user_name, user_email, active_email from $Conf{cm_global_db}.cm_users];
    print "GetGlobalUsers: SQL: $sql\n" if ($debug);

    my $sth = $cm_dbh->prepare($sql) or die "Couldn't prepare query";
    $sth->execute();
    $sth->rows;
    while (my @rows = $sth->fetchrow_array()) {
         my $cm_uid       = $rows[0];
         my $user_name    = $rows[1];
         my $user_email   = $rows[2];
         my $active_email = $rows[3];

         $Records{$user_name} = { user_uuid => $cm_uid,
                                  user_email => $user_email,
                                  active_email => $active_email,
                                };
    }
    $sth->finish();
    return(\%Records);

}
############################################################
sub GetAllCmVMs {
    my $cell = shift;
    my $what = shift;
    my $what_value = shift;

    my $conf_file   = "$FindBin::Bin/../conf/${cell}_cm.cfg";
    my $conf_ref = get_conf($conf_file);
    my %CellConf = %$conf_ref;

    my $target_db = "cm";
    my %Records = ();
    my @ExcludeProjects = split/,/,$Conf{exclude_projects};
    my %ExcludeProjects = map { $_ => 1 } @ExcludeProjects;
   
    my $limit = "";

    if ( $batch) {
        $limit = "limit $batch";
    }

    my $where_condition = qq[where deleted = 0 ];
    if ( $vpc and $what ne "sync" ) {
        $where_condition .= qq[and vpc = '$vpc' ];
    }

    if ($uuid2sync) {
       $where_condition .= qq[and uuid = '$uuid2sync' ];
    }

    if ($what eq "expired" ) {
        #$where_condition .= qq[and state != 'suspended' and expiration_date != '0000-00-00' and expiration_date <= CURDATE()];
        if (! defined $force ) {
           $where_condition .= qq[and expiration_date != '0000-00-00' and expiration_date <= CURDATE() and state not in ( 'suspended', 'stopped', 'error', 'resized' )];
        }
    }
    elsif ($what eq "unused" )  {
        $where_condition .= qq[and unused = 'true' and expiration_date is null and state != 'not_in_nova'];
    }
    elsif ($what eq "shutdown" ) {
        if (! defined $force ) {
           $where_condition .= qq[and expiration_date != '0000-00-00' and expiration_date <= DATE_SUB(CURDATE(), interval $Conf{days_to_keep_shutdown} day) and state in ( 'suspended', 'stopped' )];  # HERE might need to add other states like error ...
        }
    }
    elsif ($what eq "shutdown_reminder" ) {
        $where_condition .= qq[and expiration_date = DATE_ADD(CURDATE(), interval $Conf{days_to_remind_before_action} day)];
    }
    elsif ($what eq "delete_reminder" ) {
        my $days_to_remind_before_delete = ( $Conf{days_to_keep_shutdown} - $Conf{days_to_remind_before_action} );
        $where_condition .= qq[and expiration_date = DATE_SUB(CURDATE(), interval $days_to_remind_before_delete day) and state in ('suspended', 'stopped', 'error', 'resized')];
    }
    elsif ($what eq "match" ) {
        $where_condition .= qq[and expiration_date is null and state != 'not_in_nova' and hostname like '%$what_value%'];
    }

    my $sql = qq[select i.uuid, i.hostname, i.user_id, i.user_name, u.user_email, i.project_id, i.project_name, i.memory_mb, i.vcpus, i.disk_gb, i.compute_host, i.vpc, i.expiration_date,i.state from $CellConf{lifetime_db}.instance_lifetimes i LEFT JOIN $Conf{cm_global_db}.cm_users u on i.user_name = u.user_name $where_condition $limit];
   print "GetCMVMs: SQL: $sql\n" if ($debug);

    my $sth = $cm_dbh->prepare($sql) or die "Couldn't prepare query";
    $sth->execute();
    $sth->rows;
    while (my @rows = $sth->fetchrow_array()) {
         my $uuid         = $rows[0];
         my $hostname     = $rows[1];
         my $user_id      = $rows[2];
         my $user_name    = $rows[3];
         my $user_email   = $rows[4];
         my $project_id   = $rows[5];
         my $project_name = $rows[6];
         my $memory_mb    = $rows[7];
         my $vcpus        = $rows[8];
         my $disk_gb      = $rows[9];
         my $compute_host = $rows[10];
         my $vpc          = $rows[11];
         my $expiration_date = $rows[12];
         my $vm_state     = $rows[13];
         next if (exists($ExcludeProjects{$project_name}));
         next if ( defined $uuid2sync and "$uuid2sync" ne "$uuid");
         next if ( defined $user2sync and "$user2sync" ne "$user_name");

         $Records{$uuid} = { hostname     => $hostname,
                             user_id      => $user_id,
                             user_name    => $user_name,
                             user_email   => $user_email,
                             project_id   => $project_id,
                             project_name => $project_name,
                             memory_mb    => $memory_mb,
                             vcpus        => $vcpus,
                             disk_gb      => $disk_gb,
                             compute_host => $compute_host,
                             vpc          => $vpc,
                             expiration_date => $expiration_date,
                             vm_state     => $vm_state,
                             cell         => $cell,
        };
    }
    $sth->finish();
    return(\%Records);
}
############################################################
sub UpdateGlobalUsers  {
   my $GlobalUsers_ref = shift;
   my %GlobalUsers = %$GlobalUsers_ref;

   for my $user_name (keys %GlobalUsers ) {
       my $user_uuid = $GlobalUsers{$user_name}{user_uuid};
       my $user_email = $GlobalUsers{$user_name}{user_email};
       my $active_email = $GlobalUsers{$user_name}{active_email};
       my $sql = qq[insert into $Conf{cm_global_db}.cm_users (cm_uid, user_name, user_email, active_email) values ('$user_uuid', '$user_name', '$user_email', $active_email)];
       print "\t\tInserting GlobalUser: $user_name -> $user_email\n" ;
       my $sth = $cm_dbh->prepare($sql) or die "Couldn't prepare query";
       $sth->execute();
       $sth->finish();
   }
}
############################################################
sub GetUserID {
   my $cell      = shift;
   my $user_name = shift;

   my $conf_file   = "$FindBin::Bin/../conf/${cell}_cm.cfg";
   my $conf_ref = get_conf($conf_file);
   my %CellConf = %$conf_ref;

   my $sql = qq[select id from $CellConf{cm_os_replica_db}.user where name = '$user_name'];
   my $cm_sth = $cm_dbh->prepare($sql) or die "Couldn't prepare query";
   $cm_sth->execute();
   my $result = $cm_sth->fetchrow_hashref();
   $cm_sth->finish();
   my $user_id = $result->{id}; 
   return($user_id);
}
############################################################
sub GetGlobalUserID {
   my $user_name = shift;

   my $sql = qq[select cm_uid from $Conf{cm_global_db}.cm_users where user_name = '$user_name'];
   my $cm_sth = $cm_dbh->prepare($sql) or die "Couldn't prepare query";
   $cm_sth->execute();
   my $result = $cm_sth->fetchrow_hashref();
   $cm_sth->finish();
   my $user_id = $result->{cm_uid};
   return($user_id);
}
############################################################
sub UpdateUuids {
   my $cell = shift;
   my $what = shift;

   my $conf_file   = "$FindBin::Bin/../conf/${cell}_cm.cfg";
   my $conf_ref = get_conf($conf_file);
   my %CellConf = %$conf_ref;

   my $target_db = "cm";
   my $UUIDsToUpdate_ref = shift;
   my %UUIDsToUpdate = %$UUIDsToUpdate_ref;

   if ($what eq "insert" ) {
       #my $state = 'active';  #TODO use the state from Nova
       for my $uuid (keys %UUIDsToUpdate) {
           print "\tInserting $uuid  \n";
           $UUIDsToUpdate{$uuid}{project_name} =~ s/'/''/g;
           my $sql = "insert into $CellConf{lifetime_db}.instance_lifetimes (uuid,hostname,user_id,project_id,memory_mb,vcpus,disk_gb,compute_host,deleted,state,vpc) ".
              "values ('$uuid', '$UUIDsToUpdate{$uuid}{hostname}', '$UUIDsToUpdate{$uuid}{user_id}', ".
                      "'$UUIDsToUpdate{$uuid}{project_id}', $UUIDsToUpdate{$uuid}{memory_mb}, ".
                      "$UUIDsToUpdate{$uuid}{vcpus}, $UUIDsToUpdate{$uuid}{disk_gb}, '$UUIDsToUpdate{$uuid}{compute_host}', 0, '$UUIDsToUpdate{$uuid}{vm_state}', ".
                      "'$UUIDsToUpdate{$uuid}{vpc}')";

           my $sth = $cm_dbh->prepare($sql) or die "Couldn't prepare query";
           $sth->execute();
           $sth->finish();
       }
   }
   if ($what eq "update" ) {
       for my $uuid (keys %UUIDsToUpdate) {
           print "\tUpdating $uuid  \n";
           $UUIDsToUpdate{$uuid}{project_name} =~ s/'/''/g;
           my $sql = "update $CellConf{lifetime_db}.instance_lifetimes set hostname = '$UUIDsToUpdate{$uuid}{hostname}', user_id = '$UUIDsToUpdate{$uuid}{user_id}', ".
                     "user_name = '$UUIDsToUpdate{$uuid}{user_name}', project_id = '$UUIDsToUpdate{$uuid}{project_id}', ".
                     "project_name = '$UUIDsToUpdate{$uuid}{project_name}', memory_mb = '$UUIDsToUpdate{$uuid}{memory_mb}', ".
                     "vcpus = '$UUIDsToUpdate{$uuid}{vcpus}', disk_gb = '$UUIDsToUpdate{$uuid}{disk_gb}', compute_host = '$UUIDsToUpdate{$uuid}{compute_host}', ".
                     "vpc = '$UUIDsToUpdate{$uuid}{vpc}', state = '$UUIDsToUpdate{$uuid}{vm_state}' where uuid = '$uuid'"; 
           my $sth = $cm_dbh->prepare($sql) or die "Couldn't prepare query";
           $sth->execute();
           $sth->finish();
       }   
   }
   elsif ($what eq "email" ) {
       for my $uuid (keys %UUIDsToUpdate) {
           print "\tUpdating email for $uuid : $UUIDsToUpdate{$uuid}{user_email} \n";
           my $sql = qq[update $CellConf{lifetime_db}.instance_lifetimes set user_email = '$UUIDsToUpdate{$uuid}{user_email}' where uuid = '$uuid'];
           my $sth = $cm_dbh->prepare($sql) or die "Couldn't prepare query";
           $sth->execute(); 
           $sth->finish();
       }
   }
   elsif ($what eq "expiration_date") {
         for my $uuid (keys %UUIDsToUpdate) {
              if ( $UUIDsToUpdate{$uuid}{user_email} eq "n/a" and $Conf{no_email_users_use} !~ m/(.*)@(.*)/ ) {
                  print "Not updating $uuid as it doesn't have a valid email address\n";
                  next;
              }
              print "\tSetting $uuid to expire in $days_to_expire days\n";
              my $sql = qq[update $CellConf{lifetime_db}.instance_lifetimes set expiration_date = DATE_ADD(CURDATE(), interval $days_to_expire day) where uuid = '$uuid'];
              my $sth = $cm_dbh->prepare($sql) or die "Couldn't prepare query";
              $sth->execute();
              $sth->finish();
              logger("Updating expiration date: uuid: $uuid  Days to expire: $days_to_expire");
         }

   }
   elsif ($what eq "shutdown" ) {
       for my $uuid (keys %UUIDsToUpdate) {  
           my $sql = qq[update $CellConf{lifetime_db}.instance_lifetimes set state = 'suspended', expiration_date = CURDATE(), last_action = 'shutdown' where uuid = '$uuid']; 
           my $sth = $cm_dbh->prepare($sql) or die "Couldn't prepare query";
           $sth->execute();
           $sth->finish();
       }
   }
   elsif ($what eq "delete" ) {
       for my $uuid (keys %UUIDsToUpdate) {
           print "\tUpdating $uuid with deleted = 1\n";
           my $sql = qq[update $CellConf{lifetime_db}.instance_lifetimes set deleted = 1, state = 'deleted', deleted_at = NOW(), deleted_by = 'cm', last_action = 'delete' where uuid = '$uuid'];
           my $sth = $cm_dbh->prepare($sql) or die "Couldn't prepare query";
           $sth->execute();
           $sth->finish();
       }
   }
   elsif ($what eq "sync_delete" ) {
       for my $uuid (keys %UUIDsToUpdate) {
           print "\tUpdating $uuid with deleted = 1\n";
           my $sql = qq[update $CellConf{lifetime_db}.instance_lifetimes set deleted = 1, state = 'deleted', deleted_at = NOW(), deleted_by = 'sync' where uuid = '$uuid'];
           my $sth = $cm_dbh->prepare($sql) or die "Couldn't prepare query";
           $sth->execute();
           $sth->finish();
       }
   }

}
############################################################
sub SetVMsToExpire {  
    my $days_to_expire = shift;
    my $option = shift;
    my $option_value = shift;
    my %SelectedVMs = ();
    my $expiration_date = GetExpirationDate($days_to_expire);

    for my $cell (@AvailableCells) {
        my %CellSelectedVMs = ();
        if ( $option eq "match" ) {
            print "\tSetting VMs to expire matching $option_value\n";
            my $CellSelectedVMs_ref = GetAllCmVMs($cell, $option, $option_value);
            %CellSelectedVMs = %$CellSelectedVMs_ref;
        }
        elsif ( $option eq "unused" ) {
            #print "\tSetting VMs to expire marked as unused\n";
            my $CellSelectedVMs_ref =  GetAllCmVMs($cell, "unused");
            %CellSelectedVMs = %$CellSelectedVMs_ref;
        }
        if ( keys %CellSelectedVMs > 0 ) {
            my $number_elements = ( keys %CellSelectedVMs );
            print "\tFound $number_elements VMs from $cell\n";
            # Update DB
            if (!$noop) {
                UpdateUuids($cell, "expiration_date",\%CellSelectedVMs);
            }
            else {
                print "\tRunning in noop mode (not updating the DB)\n";
            }
        }

        @SelectedVMs{ keys %CellSelectedVMs } = values %CellSelectedVMs;    

    } # End cell loop
    ########################################################################

    my $UserEmail_VMs_List_ref = GetUserVMs(\%SelectedVMs);
    my %UserEmail_VMs_List = %$UserEmail_VMs_List_ref;

    if ( keys %UserEmail_VMs_List > 0 ) {
        SendNotification(\%UserEmail_VMs_List, "expiration", $expiration_date);
    }
    else {
        print "\tNo VMs found to have expiration date set\n";
    }

}
############################################################
sub SendReminder {
    my $notification_type = shift;
    my %SelectedVMs = ();
    my $days_to_expire = 2;  # TODO - make this configurable

    my %SelectedVMs = ();
    for my $cell (@AvailableCells) {
        print "\nSending $notification_type notification for cell: $cell ...........\n";
        my $CellSelectedVMs_ref = GetAllCmVMs($cell, $notification_type);
        my %CellSelectedVMs     = %$CellSelectedVMs_ref;
        if ( keys %CellSelectedVMs > 0 ) {
            my $number_elements = ( keys %CellSelectedVMs );
            print "\tThere $number_elements VMs for $notification_type notification for cell: $cell.\n";
        }

        @SelectedVMs{ keys %CellSelectedVMs } = values %CellSelectedVMs;

    } # End cell loop
    #################################################################################
    
    my $UserEmail_VMs_List_ref = GetUserVMs(\%SelectedVMs);
    my %UserEmail_VMs_List = %$UserEmail_VMs_List_ref;

    if ( keys %UserEmail_VMs_List > 0 ) {
        #Sending notification
        my $expiration_date = GetExpirationDate($days_to_expire);
        SendNotification(\%UserEmail_VMs_List, $notification_type, $expiration_date);
   }
   else {
       print "\tNo VMs found to be shutdown on $defined_date\n";
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
 
    my $number_elements = (keys %List); 
    print "\nSending Email Notifications to $number_elements users\n";

    if ($notification_type =~ m/reminder/ ) {
       $subject = "Reminder: $subject";
    }
    if ( $notification_type eq "unused" ) {
       $subject = $Conf{email_subject_unused};
    }
    if ($notification_type eq "delete" ) {
       $subject = $Conf{email_subject_deleted};
    }elsif ($notification_type eq "shutdown" ) {
       $subject = $Conf{email_subject_shutdown};
    }

    my $EmailTemplate = "${templates_dir}/${notification_type}.tmpl";
    for my $email (keys %List ) {
        next if (! $email );
        my $user_vms;
        my $user_id;
        my $user_name;

        for my $uuid ( keys $List{$email} ) {
            if ( $List{$email}{$uuid} ) {
               #$user_id = $List{$email}{$uuid}{user_id};
               $user_name = $List{$email}{$uuid}{user_name};
               # TODO - get user_id from the List above, do not make a call for every uuid
               $user_id = GetGlobalUserID($user_name);
               last;
            }
        }
        next if (!$user_id);

        my @EmailTemplate = `cat $EmailTemplate`;
        my $no_email_users_message = "";
        if ( "$email" eq "$Conf{no_email_users_use}" ) {
             $no_email_users_message = $Conf{no_email_users_message};
        }

        open(EMAIL_FILE, ">$email_file");
        foreach my $line (@EmailTemplate) {
            chomp($line);
            if ($line =~ m/__VMEM_URL__/ ) {               
                my $vmem_url =  "$Conf{vmem_url}?uid=$user_id";
                $line =~ s/__VMEM_URL__/$vmem_url/;
            }
            if ($line =~ m/__VM_LIST__/ ) {
                $line = "";
                # TODO: make the fields configurable
                for my $uuid ( keys $List{$email} ) {
                   $line .= qq[<tr bgcolor="#FFFFFF"><td>&nbsp; $List{$email}{$uuid}{hostname}</td><td>&nbsp; $List{$email}{$uuid}{project_name}</td><td>&nbsp; $List{$email}{$uuid}{vpc}</td><td>&nbsp; $List{$email}{$uuid}{cell}</td></tr>];
                   if ($user_vms eq "" ) {
                       $user_vms = "$List{$email}{$uuid}{hostname} ($List{$email}{$uuid}{cell})";
                   }
                   else {
                       $user_vms = "$user_vms,$List{$email}{$uuid}{hostname} ($List{$email}{$uuid}{cell})";
                   }
                }
            }
            if ($line =~ m/__EXPIRATION_DATE__/ ) {
                $line =~ s/__EXPIRATION_DATE__/$expiration_date/;
            }
            if ($line =~ m/__NO_EMAIL_USERS_MESSAGE__/ ) {
                $line =~ s/__NO_EMAIL_USERS_MESSAGE__/$no_email_users_message/;
            }
            if ($line =~ m/__EMAIL_REPLY_TO__/ ) {
                $line =~ s/__EMAIL_REPLY_TO__/$Conf{email_reply_to}/;
            }
            print EMAIL_FILE "$line\n";
        }
        close(EMAIL_FILE);

        #Send email
        $email = $debug_email if ($debug_email);
       
        $user_vms =~ s/\n/,/g;
        print "\tEmailing: $email VMS: $user_vms User_ID: $user_id\n";
        next if ($noop); 
        my $email_cmd = qq[${bin_dir}/emailer.pl -t $email -S '$subject' -f $email_file];
        my $manager_email;

        # CC to manager if notification_type is reminder and send_reminder_to_manager is true
        if ( $Conf{send_reminder_to_manager} eq "true" and $notification_type =~ m/reminder/ ) {
            $manager_email = GetEmailAddress($user_name, "manager-email");
            if ( $manager_email ne "n/a" ) {
               print "          CC to manager: $manager_email\n";
               $email_cmd = qq[${bin_dir}/emailer.pl -t $email -c $manager_email -S '$subject' -f $email_file];
            }
        }
        
        #system("${bin_dir}/emailer.pl -t $email -S '$subject' -f $email_file");
        system("$email_cmd");
        logger("Emailing: $email $manager_email  VMS: $user_vms User_ID: $user_id");
        sleep 1;
    }

}
############################################################
sub ActionOnVMs {
    my $action = shift;
    my ($cm_state, $nova_action, $expiration_date);

    if ( $action eq "shutdown" ) {
        $cm_state    = "expired";
        $nova_action = "suspend";
        $expiration_date = GetExpirationDate($Conf{days_to_keep_shutdown});
    }
    elsif ( $action eq "delete" ) {
        $cm_state    = "shutdown";  
        $nova_action = "delete";
        $expiration_date = "";
    }

    my %SelectedVMs = ();
    for my $cell (@AvailableCells) { 
        print "\nRunning $action on cell: $cell ..............\n"; 
        my $CellSelectedVMs_ref = GetAllCmVMs($cell, $cm_state);
        my %CellSelectedVMs     = %$CellSelectedVMs_ref;
        if ( keys %CellSelectedVMs > 0 ) {
            my $number_elements = ( keys %CellSelectedVMs );
            print "\tFound $number_elements VMs $cell\n";
            if ( !$noop) {

                # TODO move update for each uuid after success
             
                UpdateUuids($cell, $action, \%CellSelectedVMs);
                for my $uuid (keys %CellSelectedVMs) {
                    my $message = "Executing $action on: $uuid | hostname: $CellSelectedVMs{$uuid}{hostname} | user: $CellSelectedVMs{$uuid}{user_name} | cell: $cell";
                    print "\t$message\n";
                    logger($message);
                   
                   
                    my $nova_retries = 3;
                    if ( $Conf{nova_retries} ) {
                        $nova_retries = $Conf{nova_retries};
                    }
                    my $result;
                    while ( $nova_retries > 0 ) {
                        $result = `${bin_dir}/run_os_cmd.sh --cell $cell nova $nova_action $uuid`;
                        if ( $result ne "" ) {
                            print "Result: $uuid $result\n";
                            logger("NovaError $action: cell: $cell uuid: $uuid : $result");
                        }
                        if ( $result =~ m/HTTP 500/ ) {
                            print "  $uuid timed out. Retrying again. \n";
                            $nova_retries--;
                            sleep 2;
                        }
                        else {
                            $nova_retries = 0;
                        }
                    }
 

                    #my $result = `${bin_dir}/run_os_cmd.sh --cell $cell nova $nova_action $uuid`;
                    #if ( $result ne "" ) {
                    #    print "Result: $result\n";
                    #    logger("NovaError $action: cell: $cell uuid: $uuid : $result");
                    #}
                }
            }
            else {
                 print "\tRunning in noop mode for cell $cell (not updating the DB)\n";
            }
        }

        @SelectedVMs{ keys %CellSelectedVMs } = values %CellSelectedVMs; 

    } # End cell loop
    ####################################################################################

    if ( $noemail ) {  # Will not send notification if --noemail is used
        print "Notification will not be send\n";
    }
    else {
        my $UserEmail_VMs_List_ref = GetUserVMs(\%SelectedVMs);
        my %UserEmail_VMs_List = %$UserEmail_VMs_List_ref;
        if ( keys %UserEmail_VMs_List > 0 ) {
            SendNotification(\%UserEmail_VMs_List, $action, $expiration_date);
        }
        else {
            print "\tNo VMs found to $action on $defined_date\n";
        }  
    }
}
############################################################
sub GetEmailAddress {
   my $username = shift;
   my $who = shift;
   my $email = "n/a";

   if ( $username ne "admin" ) {
       my $result = `$Conf{ldap_query_tool} --user $username --show $who | grep '\@' | head -1`;
       chomp($result);
       if ($result ne "" ) {
           $email = $result;
       }
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
       #next if ( defined $user2sync and ($user2sync ne $LifeTimeVMs{$uuid}{user_name}) );
       #next if ( "$user2sync" ne "$LifeTimeVMs{$uuid}{user_name}" );
       next if ( defined $user2sync and $LifeTimeVMs{$uuid}{user_name} ne $user2sync );

       if ( ! $UserEmails{$LifeTimeVMs{$uuid}{user_email}} ) {
            $UserEmails{$LifeTimeVMs{$uuid}{user_email}} = 1;
       }
   }
   # List the emails and the VMs
   for my $email ( keys %UserEmails ) {
       my %UserVMs = ();
       my $user_unused_vms;
       my $user_id;
       my $user_name;
       for my $uuid (keys %LifeTimeVMs) {
           if ( $email eq $LifeTimeVMs{$uuid}{user_email} ) {
               $user_unused_vms = "$user_unused_vms,$LifeTimeVMs{$uuid}{hostname}";
               $user_id = $LifeTimeVMs{$uuid}{user_id};
               $user_name = $LifeTimeVMs{$uuid}{user_name};
               $UserVMs{$uuid} = { hostname => $LifeTimeVMs{$uuid}{hostname}, user_id => $LifeTimeVMs{$uuid}{user_id}, user_name => $LifeTimeVMs{$uuid}{user_name}, project_name => $LifeTimeVMs{$uuid}{project_name}, vpc => $LifeTimeVMs{$uuid}{vpc}, cell => $LifeTimeVMs{$uuid}{cell} }; 
           }
       }
       $user_unused_vms =~ s/^,//g;
       if ($email eq "n/a" and $Conf{no_email_users_use} =~ m/(.*)@(.*)/) {
           $email   = $Conf{no_email_users_use};
           $user_id = $Conf{admin_user_tid};
       } 
       if ( $Conf{email_domain_replace} ) {
           $email =~ s/@.*/\@$Conf{email_domain_replace}/;
       }
       if ( $email =~ m/(.*)@(.*)/ ) {
           #$Email_VMs_List{$email} = { vms => $user_unused_vms, user_id => $user_id };
           $Email_VMs_List{$email} = { %UserVMs };
       }
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
sub Report {
    my $cell = shift;
    print "==========================================================================\n";
    print "== Report for $cell ==\n";

    for my $report_name ( sort { $Reports{$a}{order} <=> $Reports{$b}{order} }keys %Reports) {
    
        if ( $report_name ne "$report" and $report ne "all" ) {
            next;
        }
 
        print "==========================================================================\n";
        print "###  $Reports{$report_name}{name}\n\n";
        my $LifeTimeVMs_ref = GetAllCmVMs($cell, $report_name);    
        my %LifeTimeVMs = %$LifeTimeVMs_ref;

        if (keys %LifeTimeVMs ) { 
        # TODO - calculate the spacing 
        for my $key (sort { $ColumnNames{$a}{order} <=> $ColumnNames{$b}{order} } keys %ColumnNames) {
            if ( $report_format eq "csv" ) {
               print "$ColumnNames{$key}{colname}^^";
            }
            else {
               print "$ColumnNames{$key}{colname} \t";
            }
        }
        print "\n";
        }

        my $total_memory = 0;
        my $total_cpus   = 0;
        my $total_disk   = 0;
        my $total_vms = keys %LifeTimeVMs;   

        for my $uuid (keys %LifeTimeVMs) {
           print "$uuid";
           for my $colname (sort { $ColumnNames{$a}{order} <=> $ColumnNames{$b}{order} } keys %ColumnNames) {
               if ( $report_format eq "csv" ) {
                   print "^^$LifeTimeVMs{$uuid}{$colname}";
               }
               else {
                   print "  $LifeTimeVMs{$uuid}{$colname}";
               }
               if ($colname eq "memory_mb" ) {
                   $total_memory = $total_memory + $LifeTimeVMs{$uuid}{$colname};
               } elsif ( $colname eq "vcpus" ) {
                   $total_cpus = $total_cpus + $LifeTimeVMs{$uuid}{$colname};
               } elsif ( $colname eq "disk_gb" ) {
                   $total_disk = $total_disk + $LifeTimeVMs{$uuid}{$colname};
               } 
           }
           print "\n";
        }
        print "\n";
        if ( $total_memory > 0 ) {
           $total_memory = comma_me($total_memory);
           $total_cpus = comma_me($total_cpus);
           $total_disk = comma_me($total_disk);
           print "Total VMs: $total_vms   Total Memory: $total_memory MB   Total CPUs: $total_cpus   Total Disk: $total_disk GB\n\n";
        }
    }
}
############################################################
sub get_conf {
   my $conf_file = shift;
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
sub comma_me {
local $_  = shift;
1 while s/^(-?\d+)(\d{3})/$1,$2/;
return $_;
}
###########################################################
sub trim {
   my @out = @_;
    for (@out) {
        s/^\s+//;
        s/\s+$//;
    }
    return wantarray ? @out : $out[0];
}
###########################################################
sub logger {
    my $message = shift;
    my $date = `date`;
    chomp($date);
    open(LOG, ">>$Conf{manager_log_file}");
    print LOG "$date: $message\n";
    close(LOG);
}
###########################################################
sub help {
   print "Options:\n";
   print "\t--report		Display a report of all actions/instances for today\n";
   print "\t--full-run		Runs: sync,set-expired,shutdown,delete,send-reminder\n";
   print "\t--set-expired		Sets VMs marked as unused to expire\n";
   print "\t--delete    		Deletes the VMs scheduled to deleted today\n";
   print "\t--sync      		Syncs lifetime with nova and keystone, deleted uuids, missing records, etc\n";
   print "\t--shutdown		Shuts down VMs scheduled to be deleted.\n";
   print "\t--uuid			Syncs a uuid from OpenStack DB. Needs to be run with --sync\n";
   print "\t--user			Filter by username. \n";
   print "\t--vpc			Filter by vpc. \n";
   print "\t--batch			Execute on a batch of uuids\n";
   print "\t--send-reminder		Send reminder for VMs to be shutdown or deleted\n";
   print "\t--noop			Does not update the DB\n";
   print "\t--debug-email		Send emails to the debug-email address only\n";
}
