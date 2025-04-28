#!/usr/bin/env perl
# vim: ts=4 noexpandtab ai
#
# File Created: Mon Apr 28 14:06:04 CEST 2025
# Copyright 2025
#
# All rights reserved
# ============================================================================|
#
# Class conventions used:
# 	- Understore prefix for private subroutines
#

### BEGIN Class ###
use strict;
use Forks::Super;
use File::Path qw(make_path);
package SDAT::core;

# Constructor options
# Format: "key" (type:default)  //comment
#	"resolution" (integer)
#	"outdir" (string)
#	"filePattern" (string)
#	"scanOpts" (list)
#	"device" (string)
#	"tessOpts" (list)
#	"OCR" (bool)
#	"hasADF" (bool:0)
#	"duplex" (bool:1) //this only applies if there is an Auto document feeder

sub new {
	# Check if all the binaries we need are available
	_checkDeps();
	my ($class, $arg) = @_;
	my $self = bless($arg, $class);
	$self->{tempDIR} = "/tmp/SDAT/$self->{filePattern}";
	make_path($self->{tempDIR}) unless (-d $self->{tempDIR});
	return $self;
}

sub _checkDeps {
	my @deps = (
		"scanimage",
		"tesseract",
		"magick",
		"img2pdf"
	);
	foreach(@deps) {
		die("\"$_\" not found in \$PATH, cannot continue\n") if system(
			"which", $_
		);
	}
}

sub scan {
	my $self = shift;
	if ($self->{hasADF} == 1) {
		push(@{$self->{scanOpts}}, ["--source", "ADF Duplex"]);
	}

	die("Failed to scan, got error: $!\n") if system(
		"scanimage", "-v", "-p", "--format=tiff",
		"-d", $self->{device},
		"--resolution", $self->{resolution},
		$self->{scanOpts},
		"--batch=$self->{tmpDIR}/$self->{filePattern}_%02d.tiff"
	);
	if ($self->{OCR} == 1) {
		my @files = glob("$self->{tmpDIR}/$self->{filePattern}*.tiff");
		Forks::Super::pmap { _OCR($_) } {timeout => 10}, @files;
	}
}

sub _OCR {
	my $self = shift;
    my $input_image = shift;
    my $output_text = shift;
    # Tesseract adds .txt itself, so we remove it if in output text
    $output_text =~ s/\.txt^//g;
    die("OCR failed: $!\n") if system(
		"tesseract",
		$input_image,
		$output_text,
		$self->{tessOpts}
	);
}

sub _writeExif {
	my $inFile = shift;
	my $inText = shift;
	die("EXIF writing failed: $!\n") if system(
		"exiv2", "-M",
		"set", "Exif.Photo.UserComment", "charset=Ascii",
		$inText,
		$inFile
	);
}

# Destructor
sub DESTROY {
}



1;  # End of file

