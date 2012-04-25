#!/usr/bin/env perl
#
# vmware_setup.pl - enables a Eucalyptus installation to use vSphere hosts

use File::Temp qw/ tempfile tempdir /;

do 'vmware_config.pl';

our %xml; # VMwareBroker configurations for different clusters

foreach my $ip (keys %cc_hosts) {
    my $part = $cc_hosts{$ip}->{part};
    $xml{$part} = ""; # zero out the XML
}
my $nparts = scalar keys %xml;
if ($nparts < 1) {
    die "did not find any partitions";
}
print "found $nparts partitions\n";

# make sure $EUCALYPTUS is set
our $eucalyptus = $ENV{'EUCALYPTUS'};
foreach my $ip (keys %cc_hosts) {
    if ($cc_hosts{$ip}->{source} eq "REPO") {
        $eucalyptus = "/";
    }
}
if (not defined $eucalyptus) { $eucalyptus = "/opt/eucalyptus"; }

# run through all vCenter-controlled hosts, add them to vCenter and configure VB to use them
if (scalar keys %vcenter_hosts > 0) {
    $have_vcenter_creds or die "unspecified url/login/password for vCenter";
    print "configuring vCenter hosts:\n";
    foreach my $ip (keys %vcenter_hosts) {
	my %spec = %{$vcenter_hosts{$ip}}; # dereference the pointer for readability
	my $password = get_esx_password(%spec);
	prep_esx_host ($ip, $esx_username, $password) and die "failed to prep esx host $ip";
	tidy_esx_host ($ip, $esx_username, $password) and die "failed to tidy esx host $ip";
	vcenter_add_host ($ip, $password) and die "failed to add host $ip to vCenter"; # add the host to vCenter using VMwareClient wrapped by vsphere_client.sh
	$xml{$spec{part}} = $xml{$spec{part}} . xml_host ($ip, $esx_username, $password, $spec{upload_via_host});
    }
    foreach my $part (keys %xml) {
	if (defined $xml{$part} and $xml{$part} ne "") {
	    $xml{$part} = xml_endpoint ($vcenter_url, $vcenter_username, $vcenter_password, $xml{$part});
	}	    
    }
}

# run through all independent ESX hosts and configure VB to use them
if (scalar keys %direct_hosts > 0) {
    $have_esx_creds or die "unspecified url/login/password for ESX hosts";
    print "configuring direct ESX hosts:\n";
    foreach my $ip (keys %direct_hosts) {
	my %spec = %{$direct_hosts{$ip}}; # dereference the pointer for readability
	my $password = get_esx_password(%spec);
	prep_esx_host ($ip, $esx_username, $password) and die "failed to prep esx host $ip";
	tidy_esx_host ($ip, $esx_username, $password) and die "failed to tidy esx host $ip";
	$xml{$spec{part}} = $xml{$spec{part}} . xml_endpoint ("https://" . $ip . "/sdk", $esx_username, $password);
    }
}

# extra options for all brokers
my $xml_extras = "";
if ($max_cores > 0) {
    $xml_extras .= " maxCores='$max_cores'";
}
if ($extras ne "") {
    $xml_extras .= " $extras";
}

print "configuring VMwareBrokers:\n";
foreach my $part (keys %xml) {
    my $xml = "<configuration>\n\t<vsphere" . $xml_extras . ">\n" . $xml{$part} . "\t</vsphere>\n"
	. "\t<paths scratchDirectory='/disk1/storage/eucalyptus/instances/vmware/work'"
	. " cacheDirectory='/disk1/storage/eucalyptus/instances/vmware/cache'/>\n"
	. "</configuration>\n";
    print "\nconfiguring VMware Broker $part with:\n$xml";
    inject_configuration ($clc_ip, $xml, $part) 
	and die "failed to update Vmware Broker's configuration on CLC";
}

foreach my $ip (keys %cc_hosts) {
    my $file = "$eucalyptus/etc/eucalyptus/eucalyptus.conf";
    #  Packages may or may not do this; it does not hurt to redo it.
    print "\tpatching configuration file $file for CC on $ip:\n";
    ssh ($ip, 'sed \'s/NC_SERVICE=\"axis2\/services\/EucalyptusNC\"/NC_SERVICE=\"\/services\/VMwareBroker\"/\' --in-place ' . $file);
    ssh ($ip, 'sed \'s/NC_PORT=\"8775\"/NC_PORT=\"8773\"/\' --in-place ' . $file);
    print "\trestarting CC so it picks up the new configuration...\n";
    ssh ($ip, $eucalyptus . '/etc/init.d/eucalyptus-cc cleanrestart');
}

print "\nsetting max VLAN index\n";
ssh ($clc_ip, "$eucalyptus/usr/sbin/euca-modify-property -p cloud.network.global_max_network_tag=$max_vlan") 
    and print "WARNING: failed to set cloud.network.global_max_network_tag on CLC!";

print "\nall VMware Brokers are configured\n";
exit(0);

sub xml_host {
    my ($ip, $username, $password, $upload_via_host) = @_;

    my $xml = "\t\t\t<host name='" . $ip . "'";
    if (defined $username) {
	$xml = $xml . " login='" . $username . "'";
    }
    if (defined $password) {
	$xml = $xml . " password='" . $password . "'";
    }
    if (defined $upload_via_host) {
	$xml = $xml . " uploadViaHost='true'";
    }
    $xml = $xml . "/>\n";
    return $xml;
}

sub xml_endpoint {
    my ($url, $username, $password, $inner_xml) = @_;

    my $xml = "\t\t<endpoint url='" . $url . "'";
    if (defined $username) {
	$xml = $xml . " login='" . $username . "'";
    }
    if (defined $password) {
	$xml = $xml . " password='" . $password . "'";
    }
    if (defined $inner_xml) {
	$xml = $xml . " discover='false'>\n$inner_xml\t\t</endpoint>\n";
    } else {
	$xml = $xml . " discover='true'/>\n";
    }
    return $xml;
}

sub inject_configuration {
    my ($ip, $xml, $part) = @_;

    ($fh, $path) = tempfile();
    print $fh $xml;
    if (ssh ($ip, 'V=\$( cat ' . $eucalyptus . 
             '/etc/eucalyptus/eucalyptus-version ); [ \$( expr match \$V \"2.0.[0-9]\" \\\| match \$V \"eee-2.0.[0-9]\" ) == 0 ]')) {
        return (scp ($ip, $path, "$eucalyptus/etc/eucalyptus/vmware_conf.xml") or 
                ssh($ip, "chown eucalyptus $eucalyptus/etc/eucalyptus/vmware_conf.xml; service eucalyptus-cloud restart"));
    } else {
        return (scp ($ip, $path, $path) 
            or ssh ($ip, "$eucalyptus/usr/sbin/euca-modify-property --property-from-file=${part}.vmwarebroker.configxml=$path"));
    }
}
