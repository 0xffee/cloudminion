#!/usr/bin/perl

use strict;
use File::Basename;
use FindBin;
use CGI qw(:standard);
use CGI::Carp qw(warningsToBrowser fatalsToBrowser);
use DBI;

my $bin_dir     = "$FindBin::Bin/../bin";
my $conf_file   = "$FindBin::Bin/../conf/cm-global.cfg";

my $conf_ref = get_conf($conf_file);
my %Conf = %$conf_ref;

my $mypid = $$;
my $cgi_script = basename($0);
my $log_file = $Conf{vmem_log_file};
my $main_title = "$Conf{datacenter} VM Expiration Manager";
my $expire_days = $Conf{days_to_expire};
my $admin_user_uid = $Conf{admin_user_uid};

my $q = new CGI;
my $params  = $q->Vars;
my $action  = $params->{'action'};
my $view    = $params->{'view'};

my $uid       = $params->{'uid'};
my $uuid      = $params->{'uuid'};
my $hostname  = $params->{'hostname'};
my $tenant    = $params->{'tenant'};
my $tenant_id = $params->{'tenant_id'};
my $new_expiration_time = $params->{'new_expiration_time'};


my %ExpirationDates = ();
$ExpirationDates{one_month}     = { name => '1 Month',       order => '1' };
$ExpirationDates{three_months}  = { name => '3 Months',      order => '2' };
$ExpirationDates{one_year}      = { name => '1 Year',        order => '3' };
#$ExpirationDates{never_expires} = { name => 'Never Expires', order => '4' };

my %bg_color = (
   0 => '#FFFFFF',
   1 => '#EFF5FB'
);

my $cm_dbh;

#a.title{font-family: Arial,Verdana; text-decoration: none; color: #E6E6E6;}
#####################################################
# HTML
my $css_code=<<END;
a.title:link {color: #E6E6E6;}
a.title:hover {color: #E6E6E6;}
a.title{font-family: Arial,Verdana; text-decoration: none; color: #CCCCCC;}

a.main:link {color: #000000;}
a.main:visited {color: #000000;}
a.main:active {color: #000000;}
a.main:hover {color: #DF0101;}
a.main{font-family: Arial,Verdana; text-decoration: none; color: #000000;}

a.list:link {color: #8A4117;}
a.list:visited {color: #8A4117;}
a.list:active {color: #8A4117;}
a.list:hover {color: #DF0101;}
a.list{font-family: Arial,Verdana; text-decoration: none; color: #8A4117; font-size: small;}
END
####################################
my $js_code=<<END_JS;
function goBack()   {
  window.history.back()
}
END_JS
####################################

print header;
print start_html(-title =>"$main_title",
                 -style => {-code => $css_code},
                 -script=>{-type=>'JAVASCRIPT', -code=>$js_code}
                 );

$cm_dbh = DBI->connect("DBI:mysql:database=$Conf{cm_global_db};host=$Conf{cm_db_host};port=$Conf{cm_db_port}", 
                        "$Conf{cm_user}", "$Conf{cm_password}",
                        {'RaiseError' => 1 });

my $user_name = GetUserName();
print_top();

if ( $user_name eq "" ) {
   print "<br>&nbsp; Error: Incorrect uid";
}
elsif (defined $uid  and ! defined $action ) {
   ListVMsForUser()
}
elsif ($action eq "change" ) {
   ChangeForm();
}
elsif ($action eq "set_as_unused" ) {
   # need to verify with cell
   #SetAsUnused();
   ListVMsForUser();
}
elsif ($action eq "update" ) {
   UpdateExpirationDate();
   ListVMsForUser();
}
elsif ($action eq "delete" ) {
   DeleteForm();
}
elsif ($action eq "delete_now" ) {
    DeleteVMNow();
}
else {
   DisplayMainView();
}

print_bottom();
print end_html;


$cm_dbh->disconnect();

#############################################################################
#############################################################################
sub print_top {
   print qq[
   <table width="100%" border='0' cellspacing='0' cellpadding='0'>
      <tr><td>
       <table width="100%" border='0'  bgcolor="#2D2D2D">
        <tr><td align='left' nowrap height='40' width='300'>
            <font size='3' color="#CCCCCC" face="Arial,Verdana"> &nbsp; <b>$main_title</b></font></td>
            <td align='left'>
             <font size='2' face="Arial,Verdana"> &nbsp; <a href="$cgi_script?uid=$uid" class="title">My Instances</a></font>
            </td>
            <td align='right'>
              <font size='2' face="Arial,Verdana" color="#CCCCCC">$user_name</font> &nbsp;
            </td>
         </tr>
        </table>
      </td></tr>
     <tr><td height="1"></td></tr>
     <tr><td>];
}
#############################################################################
sub print_bottom {
   print qq[
     </td></tr>
    </table>
   ];
}
#############################################################################
sub DisplayMainView {
    print qq[Missing uid parameter];
}
#############################################################################
sub ListVMsForUser {
   my $column_spacing = 30;
   my $user_id;
   #my $user_name;

   if ( $uid eq $admin_user_uid ) {
      $user_id = "all_users";
      $user_name = "all users";
   }
   else {
      #($user_id, $user_name) = GetUserName($uid);
      $user_id = $uid;
      #($user_name) = GetUserName($uid);
      #if ($user_id eq "admin" ) {
      #    $user_name = "all local users";
      #}
   } 

   my $user_vms_ref = GetUserVMs($user_name);
   my %UserVMs = %$user_vms_ref;
   my $total_vms = keys %UserVMs;

  print qq[
   <table width="100%" cellspacing='0' cellpadding='1'>
  <tr bgcolor="#cccccc"><td height='20'> <font size='2' face="Arial,Verdana"> &nbsp;&nbsp;&nbsp;&nbsp; Showing <b>$total_vms</b> instances owned by <b>$user_name</b> in <b>$Conf{cells}</b> regions</font></td></tr>
  <tr><td>
   <table border='0' cellspacing='0' cellpadding='2'>
     <tr  bgcolor='#659EC7'>
       <td> &nbsp; &nbsp; <font size='2' face="Arial,Verdana"><b>Instance</b></font>&nbsp;</td><td width="$column_spacing"></td>
       <td> &nbsp; &nbsp; <font size='2' face="Arial,Verdana"><b>Project</b></font></td><td width="$column_spacing"></td>
       <td> &nbsp; &nbsp; <font size='2' face="Arial,Verdana"><b>VPC</b></font></td><td width="$column_spacing"></td>
       <td> &nbsp; &nbsp; <font size='2' face="Arial,Verdana"><b>Region</b></font></td><td width="$column_spacing"></td>
       <td> &nbsp; &nbsp; <font size='2' face="Arial,Verdana"><b>Created At</b></font></td><td width="$column_spacing"></td>
       <td> &nbsp; &nbsp; <font size='2' face="Arial,Verdana"><b>State</b></font></td><td width="$column_spacing"></td>
       <td align="center"><font size='2' face="Arial,Verdana"><b>Expiration Date</b></font></td><td width="$column_spacing"></td>
       <td align="center"><font size='2' face="Arial,Verdana"><b>Actions</b></font></td></tr>];

   my $row_counter = 0;
   #foreach my $uuid (keys %UserVMs) {
   foreach my $uuid ( reverse sort { $UserVMs{$a}{expiration_date} cmp $UserVMs{$b}{expiration_date} } keys %UserVMs) {
      my $alt_color = $row_counter % 2;
      my $expiration_date = $UserVMs{$uuid}{expiration_date};

      if ( $expiration_date eq "" ) {
           $expiration_date = "n/a";
      }
      elsif ( $expiration_date eq "0000-00-00" ) {
           $expiration_date = "Never Expires";
      }
      if ( $UserVMs{$uuid}{project_name} eq "") {
           $UserVMs{$uuid}{project_name} = GetProjectName($UserVMs{$uuid}{cell}, $UserVMs{$uuid}{project_id});
      } 

      print qq[<tr bgcolor='$bg_color{$alt_color}'>
	 <td> &nbsp; &nbsp; <font size='2' face="Arial,Verdana">$UserVMs{$uuid}{hostname}</font> &nbsp; &nbsp; </td><td></td>
                 <td> &nbsp; &nbsp; <font size='2' face="Arial,Verdana">$UserVMs{$uuid}{project_name}</font></td><td></td>
                 <td> &nbsp; &nbsp; <font size='2' face="Arial,Verdana">$UserVMs{$uuid}{vpc}</font></td><td></td>
                 <td> &nbsp; &nbsp; <font size='2' face="Arial,Verdana">$UserVMs{$uuid}{cell}</font></td><td></td>
                 <td> &nbsp; &nbsp; <font size='2' face="Arial,Verdana">$UserVMs{$uuid}{created_at}</font></td><td></td>
                 <td> &nbsp; &nbsp; <font size='2' face="Arial,Verdana">$UserVMs{$uuid}{state}</font></td><td></td>
                 <td align="right"><font size='2' face="Arial,Verdana">$expiration_date</font> &nbsp; &nbsp; </td><td></td>
                 <td> &nbsp; &nbsp; <a href="?uid=$uid&action=change&cell=$UserVMs{$uuid}{cell}&uuid=$uuid" class="list">Extend VM Life</a> &nbsp; &nbsp; &nbsp;];
                   if ( $uid eq $admin_user_uid ) {
                       print qq[<a href="?uid=$uid&action=set_as_unused&uuid=$uuid" class="list">set as unused</a> &nbsp; &nbsp; &nbsp;];
                   }
                   print qq[
                     <a href="?uid=$uid&action=delete&cell=$UserVMs{$uuid}{cell}&uuid=$uuid" class="list">Delete Now</a> &nbsp; &nbsp;
                  </td></tr>];
       $row_counter++;
    }
   print qq[
     </table>
    </td></tr></table>
    <br>
    <font size='2' face="Arial,Verdana">Note: The <b>Expiration Date</b> is when the VMs will be shutdown. They will be deleted five days after that.</font>
   ];

}
#############################################################################
sub GetUserVMs {
   my $user_name = shift;
   my %UserVMs = ();
   my @AvailableCells = ();
   
   @AvailableCells = split/,/,$Conf{cells}; 

   for my $cell (@AvailableCells) {
       my $conf_file   = "$FindBin::Bin/../conf/${cell}_cm.cfg";
       next if ( ! -f $conf_file );
       my $conf_ref = get_conf($conf_file);
       my %CellConf = %$conf_ref;

       # Get user_id for each Cell
       my $cm_sql = qq[select id from $CellConf{cm_os_replica_db}.user where name = '$user_name'];
       my $cm_sth = $cm_dbh->prepare($cm_sql) or die "Couldn't prepare query";
       $cm_sth->execute();
       my $result = $cm_sth->fetchrow_hashref();
       $cm_sth->finish();
       my $user_id = $result->{id};

       # Get User VMs from each Cell Nova
       my $os_dbh = DBI->connect("DBI:mysql:database=$CellConf{nova_db};host=$CellConf{os_nova_db_host};port=$CellConf{os_nova_db_port}", 
                                 "$CellConf{os_user}", "$CellConf{os_password}",
                                 {'RaiseError' => 1 });

       my $sql = qq[select ni.uuid, ni.hostname, ni.project_id, im.value, ni.created_at, ni.vm_state from $CellConf{nova_db}.instances ni LEFT JOIN $CellConf{nova_db}.instance_metadata im on ni.uuid = im.instance_uuid where ni.deleted = '0' and ni.user_id = '$user_id' and im.key = 'project_cos'];
       my $sth = $os_dbh->prepare($sql) or die "Couldn't prepare query";
       $sth->execute();
       $sth->rows;
       my $row_number = $sth->rows;
       while (my @rows = $sth->fetchrow_array()) {
           my $uuid         = $rows[0];
           my $hostname     = $rows[1];
           my $project_id   = $rows[2];
           my $vpc          = $rows[3];
           my $created_at   = $rows[4];
           my $state        = $rows[5];
           $UserVMs{$uuid} = { hostname        => $hostname, 
                               project_id      => $project_id,
                               project_name    => '', 
                               vpc             => $vpc, 
                               created_at      => $created_at, 
                               expiration_date => '', 
                               state           => $state,
                               cell            => $cell, 
                             }; 
       }   
       $sth->finish();
       $os_dbh->disconnect();


       # Get User VMs from CloudMinion for each Cell 
       my $cm_sql = qq[select uuid, project_name, expiration_date from $CellConf{lifetime_db}.instance_lifetimes where deleted = '0' and user_id = '$user_id' order by project_name];
       my $cm_sth = $cm_dbh->prepare($cm_sql) or die "Couldn't prepare query";
       $cm_sth->execute();
       $cm_sth->rows;
       #my $row_number = $cm_sth->rows;
       while (my @rows = $cm_sth->fetchrow_array()) {
           my $uuid            = $rows[0];
           my $project_name    = $rows[1];
           my $expiration_date = $rows[2];
           my $hostname        = $UserVMs{$uuid}{hostname};
           my $state           = $UserVMs{$uuid}{state};
           my $vpc             = $UserVMs{$uuid}{vpc};
           #if ($expiration_date) {
               my $created_at = $UserVMs{$uuid}{created_at};
               $UserVMs{$uuid} = { hostname => $hostname, 
                                   project_name => $project_name, 
                                   vpc => $vpc, 
                                   created_at => $created_at, 
                                   expiration_date => $expiration_date, 
                                   state => $state, 
                                   cell  => $cell,
                                 };
           #}
       }
       $cm_sth->finish();

    } # End Cell loop

    return(\%UserVMs);
}
#############################################################################
sub GetUserName {

   my $sql = qq[select user_name from $Conf{cm_global_db}.cm_users where cm_uid = '$uid'];

   my $sth = $cm_dbh->prepare($sql) or die "Couldn't prepare query";
   $sth->execute();
   my $result = $sth->fetchrow_hashref();
   $sth->finish();
   my $user_name = $result->{user_name};
   return($user_name);
}
#############################################################################
sub GetVMName {
   my $cell = shift;
   my $uuid = shift;

   my $conf_file   = "$FindBin::Bin/../conf/${cell}_cm.cfg";
   my $conf_ref = get_conf($conf_file);
   my %CellConf = %$conf_ref; 

   my $os_dbh = DBI->connect("DBI:mysql:database=$CellConf{nova_db};host=$CellConf{os_nova_db_host};port=$CellConf{os_nova_db_port}", 
                             "$CellConf{os_user}", "$CellConf{os_password}",
                             {'RaiseError' => 1 });
   my $sql = qq[select hostname from $CellConf{nova_db}.instances where uuid = '$uuid'];
   my $sth = $os_dbh->prepare($sql) or die "Couldn't prepare query";
   $sth->execute();
   my $result = $sth->fetchrow_hashref();
   $sth->finish();
   $os_dbh->disconnect();

   my $hostname = $result->{hostname};
   return($hostname);
}
#############################################################################
sub GetVMExpirationDate {
   my $cell = shift;
   my $uuid   = shift;

   my $conf_file   = "$FindBin::Bin/../conf/${cell}_cm.cfg";
   my $conf_ref = get_conf($conf_file);
   my %CellConf = %$conf_ref;
   
   my $sql = qq[select expiration_date from $CellConf{lifetime_db}.instance_lifetimes where uuid = '$uuid'];
   my $sth = $cm_dbh->prepare($sql) or die "Couldn't prepare query";
   $sth->execute();
   my $result = $sth->fetchrow_hashref();
   $sth->finish();
   my $expiration_date = $result->{expiration_date};
   if ($expiration_date eq "0000-00-00" ) {
       $expiration_date = "Never Expires";
   }
   return("$expiration_date");
}
#############################################################################
sub GetProjectName {
   my $cell     = shift;
   my $project_id = shift;

   my $conf_file   = "$FindBin::Bin/../conf/${cell}_cm.cfg";
   my $conf_ref = get_conf($conf_file);
   my %CellConf = %$conf_ref;

   my $sql = qq[select name from $CellConf{cm_os_replica_db}.project where id = '$project_id'];
   my $sth = $cm_dbh->prepare($sql) or die "Couldn't prepare query";
   $sth->execute();
   my $result = $sth->fetchrow_hashref();
   $sth->finish();
   my $project_name = $result->{name};

   return($project_name);

}
#############################################################################
sub ChangeForm {
print "&nbsp; &nbsp; Change the current expiration date<br><br>";
    my $column_spacing = 40;
    my $cell = $params->{'cell'}; 
    my $hostname = GetVMName($cell, $uuid); 
    my $current_expiration_date = GetVMExpirationDate($cell,$uuid);
   
    print qq[
      <form action="$cgi_script?uid=$uid" method="post">
      <table border="0" cellspacing='0' cellpadding='2'>  
       <tr bgcolor='#659EC7'>
         <td>&nbsp; &nbsp; <b>Hostname</b></td><td width="$column_spacing"></td>
         <td>&nbsp; &nbsp; <b>Region</b></td><td width="$column_spacing"></td>
           <td align="right"><b>Current Expiration Date</b> &nbsp;</td><td width="$column_spacing"></td>
           <td><b>Set To Expire In</b></td><td width="$column_spacing"></td><tr>
       <tr bgcolor='$bg_color{"1"}'>
          <td height="40">&nbsp; &nbsp; $hostname</td><td></td>
          <td height="40">&nbsp; &nbsp; $cell</td><td></td>
           <td align="center">$current_expiration_date &nbsp;</td><td></td>
           <td><select name="new_expiration_time"> ];
                foreach my $key (sort { $ExpirationDates{$a}{order} <=> $ExpirationDates{$b}{order} }keys %ExpirationDates ) {
                    my $value = $ExpirationDates{$key}{name};
                    print qq[<option value="$key">$value</A>\n];
                }
      print qq[ 
         </td><td width="$column_spacing"></td></tr>
       <tr><td colspan="5" height="10"></td></tr>
       <tr><td colspan="5">&nbsp; &nbsp; <input type="hidden" name="action" value="update">
               <input type="hidden" name="uuid" value="$uuid">
               <input type="hidden" name="uid" value="$uid">
               <input type="hidden" name="cell" value="$cell">
               <input type="button" name="cancel" value="Cancel" onclick="goBack()" /> &nbsp; &nbsp;
               <input type="submit" value="Update" /></td></tr>
     </table>
       </form>];


}
#############################################################################
sub DeleteForm {
    my $column_spacing = 40;
    my $cell = $params->{'cell'};
    my $hostname = GetVMName($cell,$uuid);
    my $current_expiration_date = GetVMExpirationDate($cell,$uuid);

    print qq[
      <form action="$cgi_script?uid=$uid" method="post">
      <table border="0" cellspacing='1' cellpadding='0'>
       <tr>
          <td><table bgcolor='#659EC7'><tr>    
              <td height="100" bgcolor='$bg_color{"1"}'>&nbsp; &nbsp; Confirm that you want to delete <b>$hostname</b> &nbsp; &nbsp; </td></tr>
              </table>
          </td></tr>
       <tr><td height="10"></td></tr>
       <tr><td >&nbsp; &nbsp; <input type="hidden" name="action" value="delete_now">
               <input type="hidden" name="uuid" value="$uuid">
               <input type="hidden" name="cell" value="$cell">
               <input type="hidden" name="hostname" value="$hostname">
               <input type="hidden" name="uid" value="$uid">
               <input type="button" name="cancel" value="Cancel" onclick="goBack()" /> &nbsp; &nbsp;
               <input type="submit" value="Delete" /></td></tr>
     </table>
       </form>];


}
#############################################################################
sub UpdateExpirationDate {
   my $interval_number = 0; 
   my $cell = $params->{'cell'}; 

   my $conf_file   = "$FindBin::Bin/../conf/${cell}_cm.cfg";
   my $conf_ref = get_conf($conf_file);
   my %CellConf = %$conf_ref;

   #TODO replace the if statements with hash

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

   # check expiration table
   my $sql = qq[select uuid from $CellConf{lifetime_db}.instance_lifetimes where uuid = '$uuid'];
   my $sth = $cm_dbh->prepare($sql) or die "Couldn't prepare query";
   $sth->execute();
   $sth->rows;
   $sth->finish();
   my $row_number = $sth->rows;

   # Insert uuid into CM if it is not there
   if ( $row_number == 0 ) {
       system("$bin_dir/cm_manager.pl --cell $cell --sync --uuid $uuid > $log_file");
   }

   $sql = qq[update $CellConf{lifetime_db}.instance_lifetimes set expiration_date = $new_expiration_value where uuid = '$uuid'];
   my $sth = $cm_dbh->prepare($sql);
   $sth->execute();
   $sth->finish();
   
   my $log_message = "Update  uuid: $uuid  expiration: $new_expiration_time ($new_expiration_value) sql=$sql";
   logger("$log_message");
}
#############################################################################
sub UpdateDeletedUUID {
   my $cell = shift;
   my $uuid = shift;
   #my $cell = $params->{'cell'};

   my $conf_file   = "$FindBin::Bin/../conf/${cell}_cm.cfg";
   my $conf_ref = get_conf($conf_file);
   my %CellConf = %$conf_ref;

   my $sql = qq[update $CellConf{lifetime_db}.instance_lifetimes set deleted = 1, state = 'deleted', deleted_at = NOW(), deleted_by = 'vmem' where uuid = '$uuid'];
   my $sth = $cm_dbh->prepare($sql) or die "Couldn't prepare query";
   $sth->execute();
   $sth->finish();
   logger("Updated DB: uuid=$uuid, deleted=1, state=deleted");
}
#############################################################################
sub SetAsUnused {
   #TODO modify cm_manager.pl  to accept these args
   my $cell = shift;
   my $result = `sudo ${bin_dir}/cm_manager.pl --cell $cell --set-expired --uuid $uuid`;
   if ( $result =~ m/emailing: (.*) -- project_id: (.*) -- hosts: (.*)/) {
       my $email = $1;
       my $host = $3;
       print qq[<br>
        <font size='2' face="Arial,Verdana" color="green"> &nbsp;&nbsp; 
        $host was set as unused and will be deleted in $expire_days days. An email was sent to $email</font><br><br>];
   }
   else {
       print qq[<br>
        <font size='2' face="Arial,Verdana" color="red"> &nbsp;&nbsp; 
        The instance was not set as unused. It might belong to a tenant which is configured to not allow expiration on VMs</font><br><br>];
   }
}
#############################################################################
sub DeleteVMNow {
    my $cell = $params->{'cell'};

    my $conf_file   = "$FindBin::Bin/../conf/${cell}_cm.cfg";
    my $conf_ref = get_conf($conf_file);
    my %CellConf = %$conf_ref;

    logger("Deleting $uuid  cell: $cell  hostname: $hostname  username: $user_name");
    #print qq[<br>&nbsp; <font size='2' face="Arial,Verdana">Deleting <b>$hostname</b> now . . . </font>];
    print qq[<br>&nbsp; <font size='2' face="Arial,Verdana">Deleting <b>$hostname</b> in $cell cell now . . . </font>];

    system("$bin_dir/run_os_cmd.sh --cell $cell nova delete $uuid");
    UpdateDeletedUUID($cell, $uuid);
    print qq[<font size='2' face="Arial,Verdana"> Done</font> <br><br>];
    print qq[&nbsp; <font size='2' face="Arial,Verdana">Go back to</font> <a href="?uid=$uid" class="list">My Instances</a>];
}
#############################################################################
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
#############################################################################
sub trim {
   my @out = @_;
    for (@out) {
        s/^\s+//;
        s/\s+$//;
    }
    return wantarray ? @out : $out[0];
}
#############################################################################
sub logger {
    my $message = shift;
    my $date = `date`;
    chomp($date);
    open(LOG, ">>$log_file");
    print LOG "$date: $message\n";
    close(LOG);
}

