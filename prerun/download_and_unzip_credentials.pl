#!/usr/bin/perl
use strict;
use Cwd;

$ENV{'PWD'} = getcwd();

# does_It_Have( $arg1, $arg2 )
# does the string $arg1 have $arg2 in it ??
sub does_It_Have{
	my ($string, $target) = @_;
	if( $string =~ /$target/ ){
		return 1;
	};
	return 0;
};



#################### APP SPECIFIC PACKAGES INSTALLATION ##########################

my $clc_ip = "";

$ENV{'EUCALYPTUS'} = "/opt/eucalyptus";

my $source_lst = "";

#### read the input list

open( LIST, "../input/2b_tested.lst" ) or die "$!";
my $line;
while( $line = <LIST> ){
	chomp($line);
	if( $line =~ /^([\d\.]+)\t(.+)\t(.+)\t(\d+)\t(.+)\t\[(.+)\]/ ){
		my $this_roll = $6;
		if( does_It_Have($this_roll, "CLC") && $clc_ip eq "" ){
			$clc_ip = $1;
			$source_lst = $5;
		};
	};
};

if( $clc_ip eq "" ){
	print "[ERROR]\tCouldn't find CLC's IP !\n";
	exit(1);
};

# quick hack

if( $source_lst eq "PACKAGE" || $source_lst eq "REPO" ){
        $ENV{'EUCALYPTUS'} = "";
};

# remove whatever is currently in ./credentials
system("rm -f ../credentials/*");

system("ssh -o StrictHostKeyChecking=no root\@$clc_ip \"cd /root; rm -f admin_cred.zip\" ");

my $count = 1;

while( $count > 0 ){

	if( get_admin_credentials_and_unzip() == 0 ){
		$count = 0;
	}else{
		print "Trial $count\tCould Not Download and Unzip Admin Credentials\n";
		$count++;

		if( $count > 60 ){
			print "[TEST_REPORT]\tFAILED to Download and Unzip Admin Credentials !!!\n";
			exit(1);
		};
		sleep(1);
	};
};

print "\n";
print "\n";

### unzip the credentials on the tester
print "Unzipping the credentials in local directory\n";
chdir("../credentials");
system("unzip ./admin_cred.zip");
chdir("$ENV{'PWD'}");

print "\n";
print "\n";

print "DOWNLOADING AND UNZIPPING OF ADMIN CREDENTIALS HAS BEEN COMPLETED\n";

exit(0);


sub get_admin_credentials_and_unzip{

	print "$clc_ip :: $ENV{'EUCALYPTUS'}/usr/sbin/euca_conf --get-credentials admin_cred.zip\n";
	#Generate admin credentials
	system("ssh -o StrictHostKeyChecking=no root\@$clc_ip \"cd /root; $ENV{'EUCALYPTUS'}/usr/sbin/euca_conf --get-credentials admin_cred.zip\" ");
	sleep(10);

	### ADDED for this script	120211
	print "$clc_ip :: cd /root; unzip -o admin_cred.zip\n";
	#Unzip admin credentials
	system("ssh -o StrictHostKeyChecking=no root\@$clc_ip \"cd /root; unzip -o admin_cred.zip\" ");


	print "scp -o StrictHostKeyChecking=no root\@$clc_ip:/root/admin_cred.zip ../credentials/.";
	#Download admin credentials
	system("scp -o StrictHostKeyChecking=no root\@$clc_ip:/root/admin_cred.zip ../credentials/.");

	if( -e "../credentials/admin_cred.zip" ){
		return 0;
	};
	
	return 1;
};




# <START_DESCRIPTION>
# NAME: _download_credentials
# LANGUAGE: perl
# USAGE: _download_credentials
# REQUIREMENT : 2b_tested.pl file in ./input directory
# DESCRIPTION : This script downloads the admin credentials from CLC machine
# <END_DESCRIPTION> 
