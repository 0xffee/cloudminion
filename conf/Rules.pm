package Rules;

my %Rules = (
     Network => {
           Type            => "Hypervisor",
           Command         => "/opt/cloudminion/bin/cm_sar.pl --resource net --days 14 --threshhold 10 --domain",
           UnusedCondition => "StringMatch",
           UnusedValue     => "unused",
     }
     #LastLogin => {
     #      Type            => "GuestMount",
     #      Function        => "FileModTime",
     #      FileName        => "/var/log/wtmp",
     #      UnusedCondition => "DaysOlderThan",
     #      UnusedValue     => "30",
     #},
     #CPU  => {
     #      Type            => "Hypervisor",
     #      Command         => "<path to script>",
     #      UnusedCondition => "LessThan",
     #      UnusedValue     => "2",
     #},
     #CPUFromSA => {
     #      Type            => "GuestMount",
     #      Command         => "<path to script>",
     #      UnusedCondition => "StringMatch",
     #      UnusedValue     => "true",
     #},
);


sub GetAllRules {
    return(\%Rules);
}

1;

