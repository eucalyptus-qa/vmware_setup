#!/usr/bin/perl
use strict;
use warnings;
use Cwd qw(abs_path);
use Data::Dumper;
use lib abs_path("../share/perl_lib/EucaTest/lib");
use EucaTest  qw(test_name pass fail);
### SETUP TEST CONSTRUCT WITH DESIRED HOST and other otional params

my $local = EucaTest->new({host=> "local"});

### Read input file
my $CLC_INFO = $local->read_input_file("../input/2b_tested.lst");
my $testplan = "322";
my $testcase_id = "QA-87";

## Parse all the log files in ../artifacts looking for FAIL

my @artifacts = `ls -1 ../artifacts/*.out`;
my $failures= 0;
#$local->clear_log();
### FOR EACH OUTPUT FILE
foreach my $artifact (@artifacts) {
	#print $artifact; 
	chomp $artifact;
	open FILE, "<$artifact" or die $!;
	## GO THROUGH THE OUTPUT AND LOOK FOR FAILED
	my @slurp = <FILE>;
	
	foreach my $line (@slurp){
		if($line =~ qr/failed/){
			$local->log("[FAILURE FOUND IN]: $artifact<br>$line<br>");
			$failures++;
		}else{
			$local->log("$line");
		}
	}
}


my $status='f';
if( $failures == 0){
	$status = 'p';
}
### Call update testlink

my $exec_id = $local->update_testlink($testcase_id, $testplan);

$local->attach_artifacts($exec_id);		