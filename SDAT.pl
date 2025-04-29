#!/usr/bin/env perl
# vim: ts=4 ai
# SDAT - Scanned document archival tool
#
#Copyright Ziva-Vatra, Belgrade
#(www.ziva-vatra.com, mail: info@ziva_vatra.com)
#
# Project REPO: https://github.com/ZivaVatra/SDAT
#
#Licensed under the GNU GPL. Do not remove any information from this header
#(or the header itself). If you have modified this code, feel free to add your
#details below this (and by all means, mail me, I like to see what other people
#have done)
#
#This program is free software; you can redistribute it and/or
#modify it under the terms of the GNU General Public License (version 2)
#as published by the Free Software Foundation.
#
#This program is distributed in the hope that it will be useful,
#but WITHOUT ANY WARRANTY; without even the implied warranty of
#MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#GNU General Public License for more details.
#
#You should have received a copy of the GNU General Public License
#along with this program; if not, write to the Free Software
#Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
#
# This is a script for archival of Documents/Bills/Invoices/etc...
# It scans the page, runs OCR on the text, and saves the text to the comment field in the metadata
# This allows indexing engines (e.g. Desktop search) to know what text the document contains, allowing
# for easier searching, while keeping the original text+format as an image scan.
# It saves a PNG file into the $FINALDST folder

# Requirements:
#	tesseract (OCR)
#	sane-tools (SCANNING)
#	Exiv2 image metadata library (for adding text to comment field)
#	imageMagick tools (FORMAT CONVERSION)
#

use strict;
use lib "./";
use SDAT::core;

use POSIX "sys_wait_h";
use File::Path "make_path";
use File::Basename "fileparse";

# Global defaults
our $SCAN_DPI=0;
# Extra options for scanimage, for specific scanners
our $DEVICE;
our @EXTRAOPTS;
our $HAS_ADF;
our $OUTFORMAT = "null";
# Extra options for tesseract
our @TESSOPTS=("-l", "eng");
our $ENABLE_DUPLEX=1;
# We define this here so that it is available in the config file.
# We don't assign a value however until we have the "scanCore" class
# instantiated, after which we know what the temp path will be
our $TEMPDIR; 
# options
our $NO_OCR = 0;
if (defined($ENV{'SDAT_NO_OCR'})) {
	$NO_OCR = $ENV{'SDAT_NO_OCR'};
}
our $OCR_ENABLED = not $NO_OCR; # backwards compatibility, NO_OCR is deprecated and will be removed in future

sub usage {
	die("Usage: $0 \$configuration_file \$scanner_file \$target_folder \$target_scan_filename\n");
}
my $CONF_FILE=shift or usage(); # Configuration
my $SPROFILE=shift or usage(); # Scanner profile
our $FINALDST=shift or usage(); #destination (global for callback)
our $NAME=shift or usage(); #filename (global for callback)

# Read in config file
die("Not a valid config file ($!)\n") unless ( -f $CONF_FILE);
require $CONF_FILE;
die "Couldn't interpret the configuration file ($CONF_FILE) that was given.\nError details follow: $@\n" if $@;

die("Not a valid scanner profile ($!)\n") unless (-f $SPROFILE);
require $SPROFILE;
die "Couldn't interpret the scanner profile file ($SPROFILE) that was given.\nError details follow: $@\n" if $@;

# If DPI is still "0", we have invalid config, so cannot continue
die("Invalid configuration file detected, cannot continue.\n") if $SCAN_DPI == 0;
die("Invalid scanner profile detected, cannot continue.\n") unless defined($DEVICE);



my $RANDSTR=`head -c 20 /dev/urandom  | md5sum | cut -d' ' -f 1`;
$RANDSTR =~ s/\n//g;
$NAME =~ s/\n//g;

my $scanCore = SDAT::core->new({
	"resolution" => $SCAN_DPI,
	"outDIR" => $FINALDST,
	"filePattern" => $NAME,
	"scanOpts" => \@EXTRAOPTS,
	"device" => $DEVICE,
	"tessOpts" => \@TESSOPTS,
	"OCR" => $OCR_ENABLED,
	"hasADF" => $HAS_ADF,
	"duplex" => $ENABLE_DUPLEX,
	"outFormat" => $OUTFORMAT,
	});

# Assigned so that it is available to callback_last;
$TEMPDIR = $scanCore->{tempDIR};

# 1. Scan the images to a temporary folder
# As this can take a while, we fork
my $pid = fork();
if ($pid == 0) {
	$scanCore->scan();
	exit;
}

#While the above is scanning, we sit and wait for files to be created,
# Then process them as they arrive
my $counter = 3;
while(1) {
	sleep(1);

	# Loop through images, for each one do the OCR, and move to dest
	my @outfiles = glob("$scanCore->{tmpDIR}/$scanCore->{filePattern}*.tiff");
	# As long as the scanning pid is not dead, reset
	# counter
	if (waitpid($pid, WNOHANG) != -1) {
		$counter = 3;
	}
	if(@outfiles) {
		Forks::Super::pmap { $scanCore->OCR($_) } {timeout => 120}, @outfiles;
	}
	
	print("Waiting for processing pid\n");

	if ($counter-- <= 0) {
		print(" Finished!\n");
		# We have reached end of countdown with no files
		# and dead scanning PID, quit loop
		last;
	}
	Forks::Super::waitall(); # We wait for any children to finish their processing
}
# Finally, we check to see if callback_last function is defined. If it is, we execute
if (defined(&callback_last)) {
	callback_last();
}

# When all processing is complete, we write out our PNGs or PDFs
$scanCore->writeFormatBatch() or die("Could not write output!");

sub process {
	my $inFile = shift;
}
# When all is done, remove tmp folder
#exe("rm -rv $TPATH/scan.$RANDSTR");
