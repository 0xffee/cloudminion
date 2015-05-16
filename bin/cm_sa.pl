#!/usr/bin/perl

use File::Path qw( make_path );
use FindBin;
use Getopt::Long;
use strict;

my $conf_file = "$FindBin::Bin/../conf/cm_agent.cfg";
my $conf_ref = get_conf();
my %Conf = %$conf_ref;

if ( ! defined $Conf{instances_dir} ) {
    print "Error: instances_dir is not defined in $conf_file\n";
    exit 1;
}
if ( ! -d $Conf{instances_dir} ) {
    print "Error: instances_dir doesn't exist: $Conf{instances_dir}\n";
    exit 1;
}

if ( defined $Conf{cm_sa_dir} ) {
   if ( !-d $Conf{cm_sa_dir} ) {
       make_path $Conf{cm_sa_dir} or die "Failed to create path: $Conf{cm_sa_dir}";
   }
}
else {
   print "cm_sa_dir is not defined in $conf_file. The tool will now exit.\n";
   exit 1;
}


my $debug;
GetOptions( 'debug'   => \$debug );

##################################################################
my %Instances = ();
my $epoch = time();
my $date = `date +%Y%m%d`;
chomp($date);

my $sa_file = "$Conf{cm_sa_dir}/$date";

my $vm_ifs_ref = GetIFs();
my %VM_IFs = %$vm_ifs_ref;
my $net_stats_ref = GetNetStats();
my %NetStats = %$net_stats_ref;

open(SA_FILE, ">>$sa_file");

my @LibvirtXML_Files = `ls $Conf{instances_dir}/*/libvirt.xml`;
foreach my $xml_file ( @LibvirtXML_Files ) {
    chomp($xml_file);
    my $uuid;
    my @LibvirtXML = `cat $xml_file`;
    foreach my $line ( @LibvirtXML ) {
        if ( $line =~ m/<uuid>(.*)<\/uuid>/ ) {
            $uuid = $1;
            last;
        }
    }
    next if $uuid eq "";
    my $interface = $VM_IFs{$uuid};
    next if $interface eq "";

    print "DEBUG: uuid=$uuid if=$interface received=$NetStats{$interface}{received_bytes} transmitted=$NetStats{$interface}{transmitted_bytes}\n" if defined $debug;
    print SA_FILE "net:$epoch:$uuid:$NetStats{$interface}{received_bytes}:$NetStats{$interface}{transmitted_bytes}\n";
}
close(SA_FILE);

##############################################################################
sub GetIFs {
   my %VM_IFs = ();
    my @OVS_ouput = `ovs-vsctl -f table -- --columns=name,external-ids list interface  | grep attached`;
    foreach my $line (@OVS_ouput ) {
       chomp($line);
       $line =~ s/"//g;
       if ( $line =~ m/(\S*).*vm-id=(.*)}/ ) {
           my $interface = $1;
           my $vmid = $2;
           $VM_IFs{$vmid} = $interface;
       }
    }
    return(\%VM_IFs);
}
##############################################################################
sub GetNetStats {
   my %NetStats = ();
   my @NetDev = `cat /proc/net/dev`;
   foreach my $line (@NetDev) {
       chomp($line);
       $line =~ s/:/: /g;
       if ($line =~ m/(.*):\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)/ ) {
          my $interface = $1;
          my $received_bytes = $2;
          my $transmitted_bytes = $10;
          $interface =~ s/^\s+//;
          $interface =~ s/\s+$//;
          $NetStats{$interface} = { received_bytes => $received_bytes, transmitted_bytes => $transmitted_bytes};

       }
   }

   return(\%NetStats);
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
