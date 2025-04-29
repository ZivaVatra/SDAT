#!/usr/bin/env perl
# vim: ts=4 noexpandtab ai
#
# File Created: Mon Apr 28 14:06:04 CEST 2025
# Copyright 2025 Ziva-Vatra, Belgrade (www.ziva-vatra.com)
#
# Project Repository: https://github.com/ZivaVatra/SDAT
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
#Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.    #
# All rights reserved
# ============================================================================|
#
# Class conventions used:
# 	- Understore prefix for private subroutines
#

### BEGIN Class ###
use strict;
use Forks::Super;
$Forks::Super::ON_BUSY = 'block';
use Data::GUID;
use File::Path qw(make_path);
package SDAT::core;

# Constructor options
# Format: "key" (type:default)  //comment
#	"resolution" (integer)
#	"outDIR" (string)
#	"filePattern" (string)
#	"scanOpts" (list)
#	"device" (string)
#	"tessOpts" (list)
#	"OCR" (bool)
#	"hasADF" (bool:0)
#	"duplex" (bool:1) //this only applies if there is an Auto document feeder
#	"outFormat" (string:[png/pdf]) // we now limit to only these two

sub new {
	_checkDeps();
	my ($class, $arg) = @_;
	my $self = bless($arg, $class);

	my $GUID = Data::GUID->new()->as_string();
	$self->{tempDIR} = "/tmp/SDAT/$GUID";
	File::Path::make_path($self->{tempDIR}) unless (-d $self->{tempDIR});
	File::Path::make_path($self->{outDIR}) unless (-d $self->{outDIR});
	die("Output format $self->{outFormat} not valid, only PNG and PDF supported\n") unless (
		$self->{outFormat} =~ m/(PDF|PNG)/i
	);

	return $self;
}

sub _checkDeps {
	# Check if all the binaries we need are available
	my @deps = (
		"scanimage",
		"tesseract",
		"magick",
		"img2pdf",
		"exiv2"
	);
	foreach(@deps) {
		die("\"$_\" not found in \$PATH, cannot continue\n") if system(
			"which","-s", $_
		);
	}
}

sub scan {
	my $self = shift;
	if ($self->{hasADF} == 1) {
		push(@{$self->{scanOpts}}, "--source", "ADF Duplex");
	}

	die("Failed to scan, got error: $!\n") if system(
		"scanimage", "-v", "-p", "--format=png",
		"-d", $self->{device},
		"--resolution", $self->{resolution}
		, @{$self->{scanOpts}},
		"--batch=$self->{tempDIR}/$self->{filePattern}_%02d.png"
	);
} 

sub writeFormatBatch {
	my $self = shift;
	my @files = glob("$self->{tempDIR}/$self->{filePattern}*.png");

	if ($self->{OCR} == 1) {
		Forks::Super::pmap { $self->OCR($_) } {timeout => 120}, @files;
	}
	Forks::Super::waitall();

	if ($self->{outFormat} =~ m/PDF/i) {
		return $self->mergePDF(\@files);
	} else {
		Forks::Super::pmap { 
			$self->_writeExif($_);
		} {timeout => 120}, @files;
		return 1;
	}
}

sub mergePDF {
	# Unlike images, where each image has its OCR'd text in its EXIF header, PDFs are multipage
	# and we can't set a comment per page, so what we have to do is load up all the OCR text files
	# for each page, concatenate them and set the entire thing as a comment. I guess I will find out
	# if the PDF spec sets a limit on comment size...

	my $text;
	my $self = shift;
	my $files = shift;
	if ($self->{OCR} == 1) {
		foreach(@{$files}) {
			print "mergePDF: $_\n";
			my $textFile = $_;
			$textFile =~ s/\.png/\.OCR\.txt/;
			warn("Unable to find OCR text for '$_'! Cannot add to PDF.") unless (-f $textFile);
			open(FD, $textFile);
			while(<FD>){
				chomp;
				$text .= $_;
			}
			close(FD);
		}
	} else {
		print "NO_OCR set, skipping.\n";
		$text = "NO_OCR";
	}
	die("Failed to create PDF: $!") if system(
		"magick", 
		@{$files},
		"-define", q~pdf:Producer="SDAT - https://github.com/ZivaVatra/SDAT"~,
		"-define", q~pdf:Author="SDAT - https://github.com/ZivaVatra/SDAT"~,
		"-define", qq/pdf:Title="$self->{filePattern}"/,
		"-define", qq/pdf:Keywords="$text"/,
		"$self->{outDIR}/$self->{filePattern}.pdf");

	# From what I can see, PDF does not have the ability to set a comment field,
	# however the PDF standard does support comments, you just have to prefix '%'
	# Ideally done at the start of the PDF, but before the '%PDF-1.3' definition
	my $pdfData;
	open(FD, "$self->{outDIR}/$self->{filePattern}.pdf") or die("Failed to open PDF for read: $!");
	$pdfData = <FD>; # First line is our PDF definition
	$pdfData .= "%$text\n"; # We add our text as a PDF comment
	while(<FD>) {
		$pdfData .= $_; #Load the rest as is
	};
	close(FD);
	# Now write the data back
	open(FD, ">$self->{outDIR}/$self->{filePattern}.pdf") or die("Failed to open PDF for write: $!");
	print(FD $pdfData);
	close(FD);
	return 1;
}

sub OCR {
	my $self = shift;
    my $inputImage = shift;
    my $outputFile = $inputImage;
	$outputFile =~ s/\.png^/\.OCR/;
	# If the output file already exists, do nothing
	# Tesseract "helpfully" appends .txt to our files
	# hence the addition
	return if (-e "$outputFile.txt");
    die("OCR failed: $!\n") if system(
		"tesseract",
		$inputImage,
		$outputFile,
		$self->{tessOpts}
	);
}

sub _writeExif {
	my $self = shift;
	my $file = shift;
	my $text = $file;
	$text =~ s/\.\w+^/\.OCR\.txt/;
	die("EXIF writing failed: $!\n") if system(
		"exiv2", "-M",
		"set", "Exif.Photo.UserComment", "charset=Ascii",
		$text,
		$file
	);
}

# Destructor
sub DESTROY {
}



1;  # End of file

