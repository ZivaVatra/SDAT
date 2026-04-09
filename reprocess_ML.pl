#!/usr/bin/perl
use strict;
use warnings;

use lib "./";
use SDAT::ollamaOCR;

# Main execution
my $image_path = shift || die "Usage: $0 <image_path>\n";

my $inst = SDAT::ollamaOCR->new({
	endpoint => "http://localhost:11434/api/generate"
});


print "Starting OCR process on: $image_path\n";

# Process the image
my $ocr_result = $inst->OCR($image_path);

if ($ocr_result) {
    print "\nOCR completed successfully!\n";
    print "Extracted text:\n$ocr_result\n";
} else {
    print "\nOCR failed or returned no text.\n";
}

print "\nProcess completed.\n";
