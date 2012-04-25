#!/usr/bin/env perl
#
# vmware_cleaup.pl - cleans up a Eucalyptus installation on vCenter

do 'vmware_config.pl';

# run through all vCenter-controlled hosts, add them to vCenter and configure VB to use them
if (scalar keys %vcenter_hosts > 0) {
    $have_vcenter_creds or die "unspecified url/login/password for vCenter";
    print "removing hosts from vCenter:\n";
    foreach my $ip (keys %vcenter_hosts) {
	my %spec = %{$vcenter_hosts{$ip}}; # dereference the pointer for readability
	vcenter_remove_host ($ip) and print "WARNING: failed to remove host $ip from vCenter!"; # remove the host from vCenter using VMwareClient wrapped by vsphere_client.sh
    }
}

print "successfully cleaned up after VMware Broker\n";
exit(0);
