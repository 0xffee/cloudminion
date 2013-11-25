package Rules;

my %Rules = (
     LastLogin => {
           Type            => "GuestMount",
           Function        => "FileModTime",
           FileName        => "/var/log/wtmp",
           UnusedCondition => "DaysOlderThan",
           UnusedValue     => "30",
     },
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

