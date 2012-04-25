#!/usr/bin/env perl
#
# vmware_config.pl - parses a QA configuration file, looking for VMware-related bits
# this file is inteded to be used as a preamble to setup and teardown code 

use diagnostics;
use warnings; 
use sigtrap;
use strict;
use English;

$OUTPUT_AUTOFLUSH = 1; # no output buffering
$SIG{'__DIE__'} = sub { print STDERR "$_[0]\n"; exit(1); }; # so we return 1 instead of whatever 'die' returns

# globals: host specifications
our @all;           # list of all hosts in the test in the order of the spec
our %all;           # by-type hash of all hosts in the test
our %cc_hosts;      # by-ip hash of CC hosts
our %esx_hosts;     # by-ip hash of ESX hosts
our %direct_hosts;  # by-ip hash of ESX hosts to use without vCenter
our %vcenter_hosts; # by-ip hash of ESX hosts to use with vCenter
our %upload_hosts;  # by-ip hash of ESX hosts to which we upload directly

# globals: parameters
our $vcenter_url = "https://192.168.7.88/sdk";
our $vcenter_username = "Administrator";
our $vcenter_password = "zoomzoom";
our $vcenter_datacenter = "QA Datacenter";
our $esx_username = "root";
our $esx_password = "foobar";
our $esxi40_password = "";
our $max_vlan = 1000;
our $max_cores = 0; # zero means 'not set'
our $extras = ""; # any extras to add verbatim to XML config

# parse the test spec
open (SPEC, "../input/2b_tested.lst" ) or die "$!";
while (my $line = <SPEC> ) {
    if ($line =~ /^([\d\.]+)\t(.+)\t(.+)\t(\d+)\t(.+)\t\[([\w\s\d]+)\]/) {
	my %spec = (ip => $1,
		    distro => $2, # e.g., CENTOS, UBUNTU, VMWARE
		    version => $3, # e.g., 5.5, MAVERICK, ESX-4.1, ESXI-4.1
		    arch => $4, # 32 or 64
		    source => $5, # BZR or ?
		    role => [split(/\s/, $6)]); # CLC WS CC...
	push (@all, \%spec); # populate @all with spec struct pointers
	foreach my $type (@{$spec{role}}) {
	    push (@{$all{$type}}, \%spec); # populate %all with spec struct pointers
	}
    } elsif ($line =~ /^\s*MAX_VLAN\s*=\s*(\S+)/) {
	$max_vlan = $1;
    } elsif ($line =~ /^\s*MAX_CORES\s*=\s*(\S+)/) {
	$max_cores = $1;
    } elsif ($line =~ /^\s*VB_EXTRAS\s*=\s*(\S.*)/) {
	$extras = $1;
	if ($extras =~ /maxCores/) {
	    die "maxCores not allowed in VB_EXTRAS";
	}
	if ($extras =~ /uploadViaHost/) {
	    die "uploadViaHost not allowed in VB_EXTRAS";
	}
    } elsif ($line =~ /^\s*ESX_LOGIN\s*=\s*(\S+)/) {
	$esx_username = $1;
    } elsif ($line =~ /^\s*ESX_PASSWORD\s*=\s*(\S+)/) {
	$esx_password = $1;
    } elsif ($line =~ /^\s*VCENTER_URL\s*=\s*(\S+)/) {
	$vcenter_url = $1;
    } elsif ($line =~ /^\s*VCENTER_LOGIN\s*=\s*(\S+)/) {
	$vcenter_username = $1;
    } elsif ($line =~ /^\s*VCENTER_PASSWORD\s*=\s*(\S+)/) {
	$vcenter_password = $1;
    } elsif ($line =~ /^\s*VCENTER_DATACENTER\s*=\s*[\'\"]?(\S[^\"\'\n\r]*)[\'\"]?$/) {
	$vcenter_datacenter = $1;
    } elsif ($line =~ /^\s*VCENTER_HOSTS\s*=\s*(\S+)/) {
	populate_hash(\%vcenter_hosts, $1, "VCENTER_HOSTS");
    } elsif ($line =~ /^\s*UPLOAD_HOSTS\s*=\s*(\S+)/) {
	populate_hash(\%upload_hosts, $1, "UPLOAD_HOSTS");
    } 
}

print "using:\n";
print "\tvcenter_url='$vcenter_url'\n";
print "\tvcenter_username='$vcenter_username'\n";
print "\tvcenter_password='$vcenter_password'\n";
print "\tvcenter_datacenter='$vcenter_datacenter'\n";
print "\tesx_username='$esx_username'\n";
print "\tesx_password='$esx_password'\n";

our $have_vcenter_creds = (defined $vcenter_url and defined $vcenter_username and defined $vcenter_password);
our $have_esx_creds = (defined $esx_username and defined $esx_password);

# run through all hosts and pull out ones for VMware,
# setting their {CCs} and {upload_via_host} properties,
# and adding them to appropriate *_hosts hashes
foreach my $specp (@all) { 
    my %spec = %$specp; # dereference the pointer for readability
    my @roles = @{$spec{role}};

    # determine partitions for CCs
    foreach my $role (@roles) {
	if ($role =~ "^CC") {
	    my $part = $role;
	    $part =~ s/CC/PARTI/; # calculate partition name from CC??
	    $specp->{part} = $part;
	    defined $part or die "failed to determine partition for CC";
	}
    }

    # identify VMware host specifications
    if ($spec{distro} =~ /VMWARE/) {
	my $key = $roles[0]; # pick first role
	if ((scalar @roles != 1) or # must be the only role
	    (not $key =~ "^NC")) { # must start with NC
	    die "expecting single NC?? specification for VMware host $spec{ip}";
	}
	$key =~ s/NC/CC/; # turn it into CC key
	if (not defined $all{$key}) {
	    die "unspecified cluster $key for host $spec{ip}";
	}

	my $part = $key;
	$part =~ s/CC/PARTI/; # calculate partition name from CC??
	$specp->{part} = $part;
	defined $part or die "failed to determine partition";

	$specp->{CCs} = \@{$all{$key}}; # point to array of CCs for this VMware node
	foreach my $ccp (@{$all{$key}}) { # populate the %cc_hosts hash
	    my $ip = $ccp->{ip};
	    if (not defined $cc_hosts{$ip}) {
		$cc_hosts{$ip} = $ccp;
	    }
	}
	$esx_hosts{$spec{ip}} = $specp; # populate the %esx_hosts hash
	if (defined $upload_hosts{$spec{ip}}) {
	    $specp->{upload_via_host} = 1;
	}
	if (not defined $vcenter_hosts{$spec{ip}}) { # identify hosts not used through vCenter
	    $direct_hosts{$spec{ip}} = $specp; # populate the %direct_hosts hash
	}
	ping ($spec{ip}) and die "failed to ping host $spec{ip}!";
	print "found specification for VMware host $spec{ip} of version $spec{version} for cluster $key\n";
    }
}

if (scalar keys %esx_hosts < 1) {
    print "no ESX hosts detected, skipping VMwareBroker configuration\n";
    exit(0);
}

# get IP of the last CLC (since it will be the master at the beginning)
# dan: get IP of the first CLC now
our $clc_ip;
if (defined $all{CLC00}) {
    $clc_ip = $all{CLC00}[0]{ip};
} elsif (defined $all{CLC}) {
    $clc_ip = $all{CLC}[0]{ip};
} else {
    die "no CLC or CLC00 listed in the configuration";
}
print "will use CLC on $clc_ip\n";

###############################################################################################

sub get_esx_password {
    my (%spec) = @_;
    my $password = $esx_password;
    if ($spec{version} eq "ESXI-4.0" and defined $esxi40_password) { # special case, because our ESXi 4.0 nodes have different password
	$password = $esxi40_password;
    }
    return $password;
}

sub ping { 
    my ($ip) = @_;
    
    return system "ping -W 2 -c 1 $ip >/dev/null";
}

sub populate_hash {
    my ($hashp, $list, $name) = @_;

    foreach my $ihost (split(/,/, $list)) { # run through comma-separated list of hosts
	$ihost =~ s/\D//g; # leave only digits (e.g., '01' from 'machine01') to form index
	my $specp = $all[$ihost]; # find host specification using the index
        if (not defined $specp or $specp->{distro} ne "VMWARE") {
          return; # die "invalid host reference in $name!";
        }

	$hashp->{$specp->{ip}} = $specp; # populate the hash
    }
}

our $vsphere_client = "../share/lib/vsphere_client.sh";

sub vcenter_add_host { # attaches host to vcenter idempotently (succeeds even if already there)
    my ($ip, $password) = @_; # we pass in password b/c our ESXi 4.0 nodes have a different one

    my $host_username = $esx_username;
    if (not defined $host_username) {
	$host_username = $vcenter_username;
    }

    my $host_password = $password;
    if (not defined $host_password) {
	$host_password = $vcenter_password;
    }
	
    my $cmd = "$vsphere_client --debug"
	. " --url $vcenter_url"
	. " --username \"$vcenter_username\""
	. " --password \"$vcenter_password\""
	. " --datacenter \"$vcenter_datacenter\""
	. " --host-password \"$host_password\""
	. " --host-username \"$host_username\""
	. " --add-host $ip";

    return run ($cmd);
}

sub tidy_esx_host { # removes all VMs on all datastores of the host
    my ($ip, $username, $password) = @_;

    my $cmd = "$vsphere_client --debug"
	. " --url https://" . $ip . "/sdk"
	. " --username \"$username\""
        . " --password \"$password\""
	. " --clean-host \"*\"";

    return run ($cmd);
}

sub vcenter_remove_host { # detaches the host from vCenter
    my ($ip) = @_;

    my $cmd = "$vsphere_client --debug"
	. " --url $vcenter_url"
	. " --username \"$vcenter_username\""
	. " --password \"$vcenter_password\""
	. " --datacenter \"$vcenter_datacenter\""
	. " --remove-host $ip";

    return run ($cmd);
}

sub prep_esx_host { # prepares the host for Eucalyptus QA: ensures there is datastore and that iSCSI is configured
    my ($ip, $username, $password) = @_;

    my $cmd = "$vsphere_client --debug"
	. " --url https://" . $ip . "/sdk"
	. " --username \"$username\""
        . " --password \"$password\""
	. " --prep-host";

    return run ($cmd);
}

{
    our $ssh_opts = "-q -o StrictHostKeyChecking=no";
    
    sub scp {
	my ($ip, $from_path, $to_path) = @_;
	return run ("scp $ssh_opts $from_path root\@$ip:$to_path");
    }
    
    sub ssh {
	my ($ip, $cmd) = @_;
	return run ("ssh $ssh_opts root\@$ip \"source /root/eucarc; $cmd\"");
    }
}

sub run {
    my ($cmd) = @_;
    print "$cmd\n";
    return system $cmd;
}
