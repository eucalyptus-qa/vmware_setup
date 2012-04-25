#!/usr/bin/perl

use strict;

my $output = `whereis runat`;

if( $output =~ /runat: (.+)/ ){
	print "runat installed at $1\n";
	exit(0);
};


exit(1);

