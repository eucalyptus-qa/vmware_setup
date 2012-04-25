#!/usr/bin/env perl
#
# vmware_tidy.pl - removes VMs on ESX hosts

use File::Temp qw/ tempfile tempdir /;

do 'vmware_config.pl';

foreach my $ip (keys %esx_hosts) {
    my %spec = %{$vcenter_hosts{$ip}}; # dereference the pointer for readability
    my $password = get_esx_password(%spec);
    tidy_esx_host ($ip, $esx_username, $password) and die "failed to tidy esx host $ip";
}

print "Good news everyone! ESX hosts have been tidied.\n";
exit(0);
