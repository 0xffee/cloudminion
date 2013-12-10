#!/usr/bin/perl

use File::Basename;
use CGI qw(:standard);
use CGI::Carp qw(warningsToBrowser fatalsToBrowser);
use strict;
use DBI;

my $base_dir  = "/x/itools/cloud_minion";
my $conf_file = "${base_dir}/conf/cm.cfg";
my $conf_ref = get_conf();
my %Conf = %$conf_ref;

my $mypid = $$;
my $cgi_script = basename($0);
my $log_file = $Conf{vmem_log_file};
my $main_title = "$Conf{datacenter} VM Expiration Manager";
my $expire_days = $Conf{days_to_expire};
my $admin_user_tid = $Conf{admin_user_tid};

my $q = new CGI;
my $params  = $q->Vars;
my $action  = $params->{'action'};
my $view  = $params->{'view'};

my $user_id = $params->{'user_id'};
my $tid = $params->{'tid'};

my $uuid = $params->{'uuid'};
my $hostname = $params->{'hostname'};
my $tenant = $params->{'tenant'};
my $tenant_id = $params->{'tenant_id'};
my $new_expiration_time = $params->{'new_expiration_time'};

my %ExpirationDates = ();
$ExpirationDates{one_month}     = { name => '1 Month',       order => '1' };
$ExpirationDates{three_months}  = { name => '3 Months',      order => '2' };
$ExpirationDates{one_year}      = { name => '1 Year',        order => '3' };
$ExpirationDates{never_expires} = { name => 'Never Expires', order => '4' };

my %bg_color = (
   0 => '#FFFFFF',
   1 => '#EFF5FB'
);


#####################################################
# HTML
my $css_code=<<END;
a.title:link {color: #E6E6E6;}
a.title:hover {color: #CCCCCC;}
a.title{font-family: Arial,Verdana; text-decoration: none; color: #E6E6E6;}

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

print_top();

if ($tid ne "" and $action eq "" ) {
   #if ($action eq "update" ) {
   #   UpdateExpirationDate();
   #}
   ListVMsForUser()
}
elsif ($action eq "change" ) {
   ChangeForm();
}
elsif ($action eq "set_as_unused" ) {
   SetAsUnused();
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

#############################################################################
#############################################################################
sub print_top {
   print qq[
   <table width="100%" border='0' cellspacing='0' cellpadding='0'>
      <tr><td>
       <table width="100%" border='0'  bgcolor="#0C2B48">
        <tr><td align='left' nowrap>
            <font size='3' color="#E6E6E6" face="Arial,Verdana"> &nbsp; <b>$main_title</b></font></td></tr>
        <tr bgcolor="#2D2D2D"><td align='left'>
            <font size='2' face="Arial,Verdana"> &nbsp; <a href="$cgi_script?tid=$tid" class="title">Home</a></font>];
         if ( $tid eq $admin_user_tid ) {
            print qq[<font size='2' face="Arial,Verdana"> &nbsp; <a href="$Conf{cloudadmin_url}" class="title">CloudAdmin</a> </font>];   
         }
        print qq[
         </td></tr>
        
        </table>
      </td></tr>

     <tr><td height="1"></td></tr>
     <tr><td>

   ];
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
    print qq[Missing tid parameter];
}
#############################################################################
sub ListVMsForUser {
   my $column_spacing = 30;
   my $user_id;
   my $display_user; 

   if ( $tid eq $admin_user_tid ) {
      $user_id = "all_users";
      $display_user = "all users";
   }
   else {
      $user_id = GetUserID($tid);
      $display_user = $user_id;
      if ($user_id eq "admin" ) {
          $display_user = "all local users";
      }
   } 
   my $user_vms_ref = GetUserVMs($user_id);
   my @UserVMs = @$user_vms_ref;
   my $total_vms = @UserVMs;

  print qq[
   <table width="100%" cellspacing='0' cellpadding='1'>
  <tr bgcolor="#cccccc"><td> <font size='2' face="Arial,Verdana"> &nbsp;&nbsp; Listing VMs for <b>$display_user</b> &nbsp; &nbsp; Total VMs: $total_vms</font></td></tr>
  <tr><td>
   <table border='0' cellspacing='0' cellpadding='2'>
     <tr  bgcolor='#659EC7'>
       <td> &nbsp; &nbsp; <font size='2' face="Arial,Verdana"><b>Instance</b></font>&nbsp;</td><td width="$column_spacing"></td>
         <td> &nbsp; &nbsp; <font size='2' face="Arial,Verdana"><b>Project</b></font></td><td width="$column_spacing"></td>
         <td> &nbsp; &nbsp; <font size='2' face="Arial,Verdana"><b>Created At</b></font></td><td width="$column_spacing"></td>
          <td align="center"><font size='2' face="Arial,Verdana"><b>Expiration Date</b></font></td><td width="$column_spacing"></td>
           <td align="center"><font size='2' face="Arial,Verdana"><b>Actions</b></font></td></tr>];

   my $row_counter = 0;
   foreach my $row (@UserVMs) {
      my $alt_color = $row_counter % 2;
      my ($hostname, $uuid, $project_id, $created_at, $expiration_date) = split(/,/,$row);
      $hostname = trim($hostname);
      $uuid = trim($uuid);
      $project_id = trim($project_id);
      $created_at = trim($created_at);
      $expiration_date = trim($expiration_date);

      if ( $expiration_date eq "" ) {
           $expiration_date = "n/a";
      }
      elsif ( $expiration_date eq "0000-00-00" ) {
           $expiration_date = "Never Expires";
      }

      print qq[<tr bgcolor='$bg_color{$alt_color}'>
	 <td> &nbsp; &nbsp; <font size='2' face="Arial,Verdana">$hostname</font> &nbsp; &nbsp; </td><td></td>
                 <td> &nbsp; &nbsp; <font size='2' face="Arial,Verdana">$project_id</font></td><td></td>
                 <td> &nbsp; &nbsp; <font size='2' face="Arial,Verdana">$created_at</font></td><td></td>
                 <td align="right"><font size='2' face="Arial,Verdana">$expiration_date</font> &nbsp; &nbsp; </td><td></td>
                 <td> &nbsp; &nbsp; <a href="?tid=$tid&action=change&uuid=$uuid" class="list">change date</a> &nbsp; &nbsp; &nbsp;];
                   if ( $tid eq $admin_user_tid ) {
                       print qq[<a href="?tid=$tid&action=set_as_unused&uuid=$uuid" class="list">set as unused</a> &nbsp; &nbsp; &nbsp;];
                   }
                   print qq[
                     <a href="?tid=$tid&action=delete&uuid=$uuid" class="list">delete now</a> &nbsp; &nbsp;
                  </td></tr>];
       $row_counter++;
    }
   print qq[
     </table>
    </td></tr></table>
   ];

}
#############################################################################
sub GetUserVMs {
   my $user_id = shift;
   my @Instances;
   my $sql;

   my $dbh = DBI->connect("DBI:mysql:database=$Conf{nova_db};host=$Conf{db_host};port=$Conf{db_port}", "$Conf{readonly_user}", "$Conf{readonly_password}",
                    {'RaiseError' => 1 });
   if ( $user_id eq "all_users" ) {
       $sql = "select ni.hostname, ni.uuid, kt.name, ni.created_at, li.expiration_date from $Conf{nova_db}.instances ni LEFT JOIN $Conf{lifetime_db}.instance_lifetimes li on ni.uuid = li.uuid LEFT JOIN $Conf{keystone_db}.project kt on ni.project_id = kt.id LEFT JOIN $Conf{keystone_db}.user ku on ku.id = ni.user_id where ni.deleted = '0' order by kt.name"
   }
   elsif ( $user_id eq "admin" ) {
      $sql = "select ni.hostname, ni.uuid, kt.name, ni.created_at, li.expiration_date from nova_devqa.instances ni LEFT JOIN lifetime_devqa.vm_lifetimes li on ni.uuid = li.uuid LEFT JOIN keystone_devqa.project kt on ni.project_id = kt.id LEFT JOIN keystone_devqa.user ku on ku.id = ni.user_id where ni.deleted = '0' and ni.user_id = ku.id and kt.name != 'DemandGen' and kt.name != 'DemandGen_DB' order by kt.name";
   }
   else {
      $sql = "select ni.hostname, ni.uuid, kt.name, ni.created_at, li.expiration_date from $Conf{nova_db}.instances ni LEFT JOIN $Conf{lifetime_db}.instance_lifetimes li on ni.uuid = li.uuid LEFT JOIN $Conf{keystone_db}.project kt on ni.project_id = kt.id where ni.deleted = '0' and ni.user_id = '$user_id' order by kt.name";
   }

   my $sth = $dbh->prepare($sql) or die "Couldn't prepare query";
   $sth->execute();
   $sth->rows;
   my $row_number = $sth->rows;
   while (my @rows = $sth->fetchrow_array()) {
         my $hostname = $rows[0];
         my $uuid = $rows[1];
         my $project_id = $rows[2];
         my $created_at = $rows[3];
         my $expiration_date = $rows[4];
         push (@Instances, "$hostname, $uuid, $project_id, $created_at, $expiration_date");
    }
    $sth->finish();
    $dbh->disconnect();
    return(\@Instances);
}
#############################################################################
sub GetUserID {
   my $dbh = DBI->connect("DBI:mysql:database=$Conf{keystone_db};host=$Conf{db_host}", "$Conf{readonly_user}", "$Conf{readonly_password}",
                    {'RaiseError' => 1 });
   #Folsom
   #my $sql = "select name from tenant where id = '$tid'";
   #Grizzly
   my $sql = "select name from project where id = '$tid'";
   my $sth = $dbh->prepare($sql) or die "Couldn't prepare query";
   $sth->execute();
   my $result = $sth->fetchrow_hashref();
   $sth->finish();
   $dbh->disconnect();


   my $user_name = $result->{name};
   return($user_name);
}
#############################################################################
sub GetVMName {
   my $uuid = shift;
   my $dbh = DBI->connect("DBI:mysql:database=$Conf{nova_db};host=$Conf{db_host}", "$Conf{readonly_user}", "$Conf{readonly_password}",
                    {'RaiseError' => 1 });
   my $sql = "select hostname from instances where uuid = '$uuid'";
   my $sth = $dbh->prepare($sql) or die "Couldn't prepare query";
   $sth->execute();
   my $result = $sth->fetchrow_hashref();
   $sth->finish();
   $dbh->disconnect();

   my $hostname = $result->{hostname};
   return($hostname);
}

#############################################################################
sub GetVMExpirationDate {
   my $uuid = shift;
   my $dbh = DBI->connect("DBI:mysql:database=$Conf{lifetime_db};host=$Conf{db_host}", "$Conf{readonly_user}", "$Conf{readonly_password}",
                    {'RaiseError' => 1 });
   my $sql = "select expiration_date from instance_lifetimes where uuid = '$uuid'";
   my $sth = $dbh->prepare($sql) or die "Couldn't prepare query";
   $sth->execute();
   my $result = $sth->fetchrow_hashref();
   $sth->finish();
   $dbh->disconnect();
   my $expiration_date = $result->{expiration_date};
   if ($expiration_date eq "0000-00-00" ) {
       $expiration_date = "Never Expires";
   }
   return("$expiration_date");
}

#############################################################################
sub ChangeForm {
print "&nbsp; &nbsp; Change the current expiration date<br><br>";
    my $column_spacing = 40;
    my $hostname = GetVMName($uuid);
    my $current_expiration_date = GetVMExpirationDate($uuid);
   
    print qq[
      <form action="$cgi_script?tid=$tid" method="post">
      <table border="0" cellspacing='0' cellpadding='2'>  
       <tr bgcolor='#659EC7'>
         <td>&nbsp; &nbsp; <b>Hostname</b></td><td width="$column_spacing"></td>
           <td align="right"><b>Current Expiration Date</b> &nbsp;</td><td width="$column_spacing"></td>
           <td><b>Set To Expire In</b></td><td width="$column_spacing"></td><tr>
       <tr bgcolor='$bg_color{"1"}'>
          <td height="40">&nbsp; &nbsp; $hostname</td><td></td>
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
               <input type="hidden" name="tid" value="$tid">
               <input type="button" name="cancel" value="Cancel" onclick="goBack()" /> &nbsp; &nbsp;
               <input type="submit" value="Update" /></td></tr>
     </table>
       </form>];


}
#############################################################################
sub DeleteForm {
    my $column_spacing = 40;
    my $hostname = GetVMName($uuid);
    my $current_expiration_date = GetVMExpirationDate($uuid);

    print qq[
      <form action="$cgi_script?tid=$tid" method="post">
      <table border="0" cellspacing='1' cellpadding='0'>
       <tr>
          <td><table bgcolor='#659EC7'><tr>    
              <td height="100" bgcolor='$bg_color{"1"}'>&nbsp; &nbsp; Confirm that you want to delete <b>$hostname</b> &nbsp; &nbsp; </td></tr>
              </table>
          </td></tr>
       <tr><td height="10"></td></tr>
       <tr><td >&nbsp; &nbsp; <input type="hidden" name="action" value="delete_now">
               <input type="hidden" name="uuid" value="$uuid">
               <input type="hidden" name="hostname" value="$hostname">
               <input type="hidden" name="tid" value="$tid">
               <input type="button" name="cancel" value="Cancel" onclick="goBack()" /> &nbsp; &nbsp;
               <input type="submit" value="Delete" /></td></tr>
     </table>
       </form>];


}
#############################################################################
sub UpdateExpirationDate {
   my $interval_number = 0; 

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
   my $dbh = DBI->connect("DBI:mysql:database=$Conf{lifetime_db};host=$Conf{db_host}", "$Conf{lifetime_user}", "$Conf{lifetime_password}",
                    {'RaiseError' => 1 });
   my $sql = "select uuid from instance_lifetimes where uuid = '$uuid'";
   my $sth = $dbh->prepare($sql) or die "Couldn't prepare query";
   $sth->execute();
   $sth->rows;
   $sth->finish();
   my $row_number = $sth->rows;

   if ( $row_number == 0 ) {
       $sql = "insert into instance_lifetimes (uuid, expiration_date) values ('$uuid', $new_expiration_value)";
   }
   else {
       $sql = "update instance_lifetimes set expiration_date = $new_expiration_value where uuid = '$uuid'";
   }
   my $sth = $dbh->prepare($sql);
   $sth->execute();
   
   $sth->finish();
   $dbh->disconnect();
   
   my $log_message = "Update  uuid: $uuid  expiration: $new_expiration_time ($new_expiration_value)";
   logger("$log_message");
}
#############################################################################
sub SetAsUnused {
   #TODO modify cm_manager.pl  to accept these args
   my $result = `sudo ${base_dir}/bin/cm_manager.pl --set-expired --u $uuid`;
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
   #print "DEBUG: $result";
}
#############################################################################
sub DeleteVMNow {
    print "Deleting $hostname now . . . ";
    system("$base_dir/bin/run_os_cmd.sh nova delete $uuid");
    print "Done <br><br>";
    print qq[<a href="?tid=$tid" class="list">View all VMs</a>];
    logger("Deleting $uuid");
}
#############################################################################
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

