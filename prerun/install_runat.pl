#!/usr/bin/perl

system("sudo gcc runat.c -o /bin/runat");

my $rc = $? >> 8;

if( $rc == 1) {
	exit(1);
};
exit(0);

