#!/usr/bin/env perl
# vim: ts=4 ai
# SDAT - Scanned document archival tool
#
#Copyright 2020 Ziva-Vatra, Belgrade
#(www.ziva-vatra.com, mail: info@ziva_vatra.com)
#
# Project URL: http://www.ziva-vatra.com/index.php?aid=71&id=U29mdHdhcmU=
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

use POSIX "sys_wait_h";
use File::Path "make_path";
use File::Basename "fileparse";

# Global defaults
our $SCAN_DPI=0;
# Extra options for scanimage, for specific scanners
our $DEVICE;
our $EXTRAOPTS="";
our $HAS_ADF;
# Extra options for tesseract
our $TESSOPTS=" -l eng ";

# options
our $NO_OCR = 0;
if (defined($ENV{'SDAT_NO_OCR'})) {
	$NO_OCR = $ENV{'SDAT_NO_OCR'};
}
require "./lib/core.pm";

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
die("Invalid sprofile detected, cannot continue.\n") unless defined($DEVICE);


my $TPATH="/tmp/scanning/";
if (! -d $TPATH) {
	print("Creating temporary path\n");
	make_path($TPATH);
}
if (! -d $FINALDST) {
	print("Creating output path\n");
	make_path($FINALDST);
}



my $RANDSTR=`head -c 20 /dev/urandom  | md5sum | cut -d' ' -f 1`;
$RANDSTR =~ s/\n//g;

$NAME =~ s/\n//g;


sub process_file {
	my $_infile = shift;
	# Parse out the file
	my ($filename, $dirs, $suffix) = fileparse($_infile, qr/\.[^.]*/);

	# ocr the image, save to text file, if NO_OCR is false
	if ($NO_OCR == 0) {
		waituntildone(ocrit("$_infile","$dirs/$filename", $TESSOPTS));
	}

	# Convert to png
	my $pngfile = $filename;
	$pngfile =~ s/$RANDSTR/$NAME/g;
	$pngfile .= ".png";
	
	print("Filename: $filename, dirs: $dirs, suffix: $suffix pngfile: $pngfile\n");

	topng("$_infile","$dirs/$pngfile");

	addComment("$dirs/$filename.txt","$dirs/$pngfile");

	exe("mv -v $dirs/$pngfile $FINALDST/");
	# Once all done, remove the infile
	unlink($_infile);

	return 0;
}
	


#Create the tmpdir if it doesn't exist
unless (-e "$TPATH/scan.$RANDSTR/") { make_path("$TPATH/scan.$RANDSTR/"); }

# 1. Scan the images to a temporary folder
# As this can take a while, we fork
my $pid = fork();
if ($pid == 0) {
	if($HAS_ADF) {
		exit(scanit_adf($SCAN_DPI,"$TPATH/scan.$RANDSTR/", $RANDSTR, $EXTRAOPTS, $DEVICE));
	} else {
		exit(scanit($SCAN_DPI,"$TPATH/scan.$RANDSTR/", $RANDSTR, $EXTRAOPTS, $DEVICE));
	}
}

#While the above is scanning, we sit and wait for files to be created,
# Then process them as they arrive
my $counter = 3;
while(1) {
	sleep(5); # 5 second wait

	#2. Loop through images, for each one do the OCR, and move to dest
	my @outfiles = `find $TPATH/scan.$RANDSTR/*.tiff 2>/dev/null`;
	my @pids;
		
	# As long as the scanning pid is not dead, reset
	# counter
	if (waitpid($pid, WNOHANG) != -1) {
		$counter = 3;
	}

	foreach(@outfiles) {
		# Every time we have a file, we reset the counter
		s/\n//g;
		print("Processing image $_\n");
	
		my $pid = fork();
		if ($pid == 0) {
			exit(process_file($_));
		} else {
			push(@pids, $pid);
		}
			
	}
	print("Waiting for processing pid\n");
	foreach(@pids) {
		print(" $_");
		waituntildone($_);
	}
	if ($counter-- <= 0) {
		print(" Finished!\n");
		# We have reached end of coutdown with no files
		# and dead scanning PID, quit loop
		last;
	}
}
# Finally, we check to see if callback_last function is defined. If it is, we execute
if (defined(&callback_last)) {
	callback_last();
}

# When all is done, remove tmp folder
exe("rm -rv $TPATH/scan.$RANDSTR");
