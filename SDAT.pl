#!/bin/env perl
# vim: ts=4 ai
# SDAT - Scanned document archival tool
#
#Copyright 2015 Ziva-Vatra, Belgrade
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
use POSIX "sys_wait_h";
# Global vars

$TPATH="/tmp/scanning/";
$DEVICE=`scanimage -L | awk '{ print \$2 }'`;
$DEVICE =~ s/\`//;
$DEVICE =~ s/\'//;
$DEVICE =~ s/\n//;
print "Using Device: $DEVICE\n";

$RANDSTR=`head -c 20 /dev/urandom  | md5sum | cut -d' ' -f 1`;
$RANDSTR =~ s/\n//g;

$FINALDST="./scans/";
$NAME=shift; #filename, first argument given to script
$NAME =~ s/\n//g;

sub exe {
    my $cmd = shift;
	if ( -f "./env.sh") {
		print "Using environement source\n";
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

sub reset_scanner {
	my $rc =  system("./reset-epsonv330");
	if ( $rc != 0 ) {
		print "WARNING: Could not run ./reset-epsonv330 to reset the USB bus. Attempting to continue, but next scan may hang...";
		return 0;
	}
	$DEVICE=`scanimage -L | awk '{ print \$2 }'`;
	$DEVICE =~ s/\`//;
	$DEVICE =~ s/\'//;
	$DEVICE =~ s/\n//;
}

sub scanit {
	my $mode = $_[0];
	my $resolution = $_[1];
	my $output = $_[2];

    #exe("scanimage  -v -p --format=tiff --mode $mode -d $DEVICE --resolution $resolution > $output");
	
	# Sometimes scanimage hangs, so we have to fork again, and monitor with timeout (60 seconds?)
	
    my $pid = fork();
	if ($pid == 0) {
#		print "scanimage  -v -p --format=tiff --mode $mode -d $DEVICE --resolution $resolution > $output";
	   exec("scanimage  -v -p --format=tiff --mode $mode -d $DEVICE --resolution $resolution > $output") or die ("could not scan!\n");
	}
	   
	my $time = time();
	print "Waiting for scanning to finish\n";
	sleep 1;
	while ((time() - $time) < 60 ) {
		if ( waitpid($pid,1) == -1 ) { 
			printf('\n');
			return(0); 
		}
		sleep 1;
		print '.';
	}

	print "Error! Timeout exceeded! Killing and continuing...\n";
	kill("TERM",$pid);
	sleep 1;
	kill("KILL",$pid); #Scanimage will abort if it gets two SIGTERM's
	reset_scanner();
	return(0);
}

sub s600dpi_col {
    scanit("color",600,$_[0]);
}

sub s600dpi_gr {
    scanit("gray",600,$_[0]);
}

sub s1200dpi_gr {
     scanit("gray",1200,$_[0]);
}

sub ocrit {
	my $input_image = shift;
	my $output_text = shift;
    return bgexe("tesseract $input_image $output_text --tessdata-dir /usr/share/tessdata/  -l eng ");
}

sub topng {
	my $input = shift;
	my $output = shift;
    exe("convert -compress Zip $input $output");
}

sub addComment {
	my $input_text = shift;
	my $output_image = shift;
#	my $comment = "";
#	open(FILE,$input_text);
#	open(OUTFILE,">$input_texit\_munged");
#	while (<FILE>) {
#		s/\n/ -- /g; 
#		print OUTFILE $_;
#		$comment .= $_;
#	}
#	close(FILE);
#	close(OUTFILE);

#	exe("exiv2 -M\"set Exif.Photo.UserComment charset=Ascii '\`cat $input_text\_munged\`' \" $output_image");
	exe("exiv2 -M\"set Exif.Photo.UserComment charset=Ascii \`cat $input_text\` \" $output_image");
}

sub waituntildone {
	my $pid = shift;
	return waitpid($pid,0) ;
}

print("Hit enter to scan (filename: $NAME ), CTRL-C to cancel");
$_ = <STDIN>;

#Create the tmpdir if it doesn't exist
unless (-e $TPATH) { mkdir($TPATH); }

#1. Scan the image (gray for OCR)
s600dpi_gr("$TPATH/scan_gr.$RANDSTR.tif");

#2. Scan the colour image we will store
my $scanpid = fork();
if ($scanpid == 0) {
	s600dpi_col("$TPATH/scan_col.$RANDSTR.tif");
	exit();
} 


#3 ocr the image
ocrit("$TPATH/scan_gr.$RANDSTR.tif","$TPATH/scan_txt.$RANDSTR");

#4 wait for the color scan to finish
waituntildone($scanpid);


# Right, the below needs no user input, so we can just fork and exit the program.
# this way we can go to the next scan while this does work in the background

#my $pid = fork();
#if ($pid == 0) {
	#ok, all done! Now convert to png and add text
	topng("$TPATH/scan_col.$RANDSTR.tif","$TPATH/$NAME.png");

	addComment("$TPATH/scan_txt.$RANDSTR.txt","$TPATH/$NAME.png");

	exe("mv -v  $TPATH/$NAME.png $FINALDST/");
	exe("rm -v $TPATH/*$RANDSTR*");
#} else {
#
# Display the finished article
my $pid = fork();
if ($pid == 0) {
	system("display -sample 750 $FINALDST/$NAME.png");
	exit(0);
} else {
exit 0;
}
#}


