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

	if ($self->outFormat =~ m/PDF/i) {
		$self->mergePDF(@files);
	} else {
		Forks::Super::pmap { 
			$self->_writeExif($_);
		} {timeout => 120}, @files;
	}
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

