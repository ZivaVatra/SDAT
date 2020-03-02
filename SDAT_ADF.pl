#!/usr/bin/perl
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

use warnings;
use strict;
use POSIX "sys_wait_h";
use File::Path "make_path";
use File::Basename "fileparse";


my $FINALDST=shift or die("Usage: $0 \$target_folder \$target_scan_filename\n"); #destination, first argument given to script
my $NAME=shift or die("Usage: $0 \$target_folder \$target_scan_filename\n"); #filename, second argument given to script


# Global variables
my $SCAN_DPI=600;
# Extra options for scanimage, for specific scanners
my $EXTRAOPTS=" --ald=no --df-action Stop --swdeskew=no --swcrop=no --buffermode On --prepick On ";
# These extra opts are for A4 paper size (defined as 210x297mm
$EXTRAOPTS .= " --page-height 320 --page-width 211 -x 211 -y 300 ";
#And these for A5 (defined as 148 x 210mm)
#$EXTRAOPTS .= " --page-height 211 --page-width 150 -x 150 -y 211 ";


my $TPATH="/tmp/scanning/";
if (! -d $TPATH) {
	print("Creating temporary path\n");
	make_path($TPATH);
}
if (! -d $FINALDST) {
	print("Creating output path\n");
	make_path($FINALDST);
}



my $DEVICE=`scanimage -f %d`;
$DEVICE =~ s/\`//;
$DEVICE =~ s/\'//;
$DEVICE =~ s/\n//;
print "Using Device: $DEVICE\n";

my $RANDSTR=`head -c 20 /dev/urandom  | md5sum | cut -d' ' -f 1`;
$RANDSTR =~ s/\n//g;

$NAME =~ s/\n//g;

sub exe {
    my $cmd = shift;
	if ( -f "./env.sh") {
		print "Using environment source\n";
	    die("Could not execute $cmd, quitting\n") unless ( 0 == system("source ./env.sh && $cmd") );
	} else {
	    die("Could not execute $cmd, quitting\n") unless ( 0 == system($cmd) );
	}
}

sub bgexe {
    #As above, but execute in the background (fork and exec)
    my $cmd = shift;
    my $pid = fork();
        if ($pid == 0) {
            #we are the child
            exec($cmd) or print STDERR "couldn't exec $cmd: $!\n";
        } else {
        return $pid;
    }
}

sub scanit_adf {
	my $mode = $_[0];
	my $resolution = $_[1];
	my $o_folder = $_[2];
	my $o_pattern = $_[3];

	die("Could not scan!\n") unless (0 == system(
		"scanimage -v -p --format=tiff $EXTRAOPTS --mode $mode -d \"$DEVICE\" --resolution $resolution --source \"ADF Duplex\" --batch=$o_folder/$o_pattern\_%02d.tiff"
	));
	return 0;
}

sub ocrit {
	my $input_image = shift;
	my $output_text = shift;
    return bgexe("tesseract $input_image $output_text --tessdata-dir /usr/share/tesseract-ocr/  -l eng ");
}

sub topng {
	my $input = shift;
	my $output = shift;
    exe("convert -compress Zip $input $output");
}

sub addComment {
	my $input_text = shift;
	my $output_image = shift;
	exe("exiv2 -M\"set Exif.Photo.UserComment charset=Ascii \`cat $input_text\` \" $output_image");
}

sub waituntildone {
	my $pid = shift;
	return waitpid($pid,0) ;
}


sub process_file {
	my $_infile = shift;
	# Parse out the file
	my ($filename, $dirs, $suffix) = fileparse($_infile, qr/\.[^.]*/);

	# ocr the image, save to text file
	waituntildone(ocrit("$_infile","$dirs/$filename"));

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

	# TODO, make this an option
	#return system("display -sample 750 $FINALDST/$pngfile");
	return 0;
}
	


#Create the tmpdir if it doesn't exist
unless (-e "$TPATH/scan.$RANDSTR/") { make_path("$TPATH/scan.$RANDSTR/"); }

# 1. Scan the images to a temporary folder
# As this can take a while, we fork
my $pid = fork();
if ($pid == 0) {
	exit(scanit_adf("color",$SCAN_DPI,"$TPATH/scan.$RANDSTR/", $RANDSTR));
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
	
	print("Waiting for processing pid:");
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
# When all is done, remove tmp folder
exe("rm -rv $TPATH/scan.$RANDSTR/");
