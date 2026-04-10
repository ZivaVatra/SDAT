#!/usr/bin/perl
use strict;
use warnings;

package SDAT::ollamaOCR;

use LWP::UserAgent;
use JSON;
use File::Slurp qw(read_file);
use MIME::Base64 qw(encode_base64);;
use Image::Magick;
use File::Path qw(remove_tree);


# Constructor options:
#   "model" (string) // The model to use, defaults to glm-ocr:latest
#   "endpoint" (string)  // The endpoint URL of our ollama RPC server (default http://localhost:11434/api/generate)
#   "DEBUG" (bool) // verbose/debug output
sub new {
	my ($class, $arg) = @_;
	my $self = bless($arg, $class);
	$self->{endpoint} //= "http://localhost:11434/api/generate";
	$self->{model} //= "glm-ocr:latest";
	$ENV{DEBUG} //= 0;
	return $self;
}

sub _resize_image_if_needed {
	my $self = shift;
	my $image_path = shift;
	# Above 2048px the glm-ocr model goes a bit screwy. 1024 is decent
	# but anything <2048 that is divisible by 16 will work. higher resolutions
	# will pick out smaller writing and better OCR, but longer execution time.
	#
	# Although I've found that I get 500 errors (assertion errors) on sizes
	# >= 1600, hence we stick with a smaller size.
	#
	# Update: seems others have noticed this: https://github.com/ollama/ollama/issues/14171
	#
	my $max_size = 1600;

	# Read image with Image::Magick to get dimensions
	my $image = Image::Magick->new();
	my $status = $image->Read($image_path); #Returns number of images read in (should be 1)
	
	if ($status == 0) {
		warn "Failed to read image: $status\n";
	}
	
	my $width = $image->Get('width');
	my $height = $image->Get('height');
	
	print "Original image size: $width × $height\n" if ($ENV{DEBUG} == 1);
	
	# Check if resize is needed
	if ($width > $max_size || $height > $max_size) {
		print "Image is too large, resizing...\n" if ($ENV{DEBUG} == 1);
		
		# Calculate scaling factor while maintaining aspect ratio
		my $scale = $max_size / ( $width > $height ? $width : $height );
		my $new_width = int($width * $scale);
		my $new_height = int($height * $scale);
		
		print "Resizing to: $new_width × $new_height\n" if ($ENV{DEBUG} == 1);
		
		# Resize the image
		$image->Scale(width => $new_width, height => $new_height);
		
		# Create output path
		my $output_path = $image_path;
		$output_path =~ s/(\.[^.]+)$/_resized$1/;
		
		# Save resized image
		$status = $image->Write(filename => $output_path, quality => 95); # Should output number of images written (1)
		if ($status == 0) {
			die "Failed to write resized image: $status\n";
		}
		
		print "Resized image saved to: $output_path\n" if ($ENV{DEBUG} == 1);
		return $output_path;
	} else {
		print "Image size is within limits, no resizing needed\n" if ($ENV{DEBUG} == 1);
		return $image_path;
	}
}

sub OCR {
	my $self = shift;
	my ($image_path) = @_;
	
	# Resize image if needed
	my $processed_image = $self->_resize_image_if_needed($image_path);
	
	# Read and encode image
	my $image_data = read_file($processed_image, binmode => ':raw');
	my $encoded_image = encode_base64($image_data, '');
	
	print "Sending image to OCR model...\n" if ($ENV{DEBUG} == 1);
	
	# Send request to ollama and await response
	my $ua = LWP::UserAgent->new(timeout => 120);
	my $request_data = {
		model => $self->{model},
		prompt => "Text Recognition: Extract all text from this image and return only the text content without any additional explanation or formatting. If you can not extract the text respond with 'Cannot OCR text' only.",
		images => [$encoded_image],
		stream => JSON::false,
		options => {
			temperature => 0.1,
			top_p => 0.1,
		}
	};
	
	my $request = HTTP::Request->new(POST => $self->{endpoint});
	$request->header('Content-Type' => 'application/json');
	$request->content(to_json($request_data));
	
	my $response = $ua->request($request);
	
	# Clean up the temporary resized image
	if ($processed_image ne $image_path) {
		print "Cleaning up temporary resized image: $processed_image\n" if ($ENV{DEBUG} == 1);
		unlink $processed_image or warn "Warning: Could not delete $processed_image: $!";
	}
	
	if ($response->is_success) {
		my $json_response = from_json($response->decoded_content);
	
		if (exists $json_response->{response} && $json_response->{response}) {
			if ($ENV{DEBUG} == 1) {	
				print "\n=== OCR RESULT ===\n";
				print $json_response->{response};
				print "\n";
			}
			return $json_response->{response};
		} else {
			if ($ENV{DEBUG} == 1) {	
				print "\n=== NO TEXT FOUND ===\n";
				print "The model returned no text content.\n";
				print "Response details: " . $response->decoded_content . "\n";
			}
			return "";
		}
	} else {
		print "Request failed: " . $response->status_line . "\n";
		print "Error details: " . $response->decoded_content . "\n";
		return "";
	}
}
1;
