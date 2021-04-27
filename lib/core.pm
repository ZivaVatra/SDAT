use strict;
use warnings;

sub waituntildone {
    my $pid = shift;
    return waitpid($pid,0) ;
}

sub scanit_adf {
	my $resolution = shift;
	my $o_folder = shift;
	my $o_pattern = shift;
	my $extraopts = shift;
	my $device = shift;

	die("Could not scan!\n") if system(
		"scanimage -v -p --format=tiff $extraopts -d \"$device\" --resolution $resolution --source \"ADF Duplex\" --batch=$o_folder/$o_pattern\_%02d.tiff"
	);
	return 0;
}

sub scanit {
	my $resolution = shift;
	my $o_folder = shift;
	my $o_pattern = shift;
	my $extraopts = shift;
	my $device = shift;

	mkdir($o_folder) unless (-d $o_folder) or die("Could not create output dir $o_folder\n"); # Create the output folder if it doesn't exist

	# Sometimes scanimage hangs, so we have to fork again, and monitor with timeout (60 seconds)
	my $pid = fork();
	if ($pid == 0) {
	   exec("scanimage -v -p --format=tiff $extraopts -d \"$device\" --resolution $resolution > $o_folder/$o_pattern.temptiff") or die ("could not scan!\n");
	}

	my $time = time();
	print "Waiting for scanning to finish\n";
	sleep 1;
	while ((time() - $time) < 60 ) {
		if ( waitpid($pid,1) == -1 ) {
			# If we reach this point, it means we completed the scan, we rename the file ext to "tiff" to make the processing code aware its ready.
			rename("$o_folder/$o_pattern.temptiff", "$o_folder/$o_pattern.tiff");
			return(0);
		}
		sleep 1;
	}

	print "Error! Timeout exceeded! Killing and continuing...\n";
	kill("TERM",$pid);
	sleep 1;
	kill("KILL",$pid); #Scanimage will abort if it gets two SIGTERM's

	rename("$o_folder/$o_pattern.temptiff", "$o_folder/$o_pattern.tiff");
	return(0);
}

# OCR commands

sub ocrit {
	my $input_image = shift;
	my $output_text = shift;
	my $tessopts = shift;
	# Tesseract adds .txt itself, so we remove it if in output text
	$output_text =~ s/\.txt^//g;
	exe("tesseract $input_image $output_text $tessopts");
	return 1; # Return true
}

sub topng {
	my $input = shift;
	my $output = shift;
	exe("convert -compress Zip $input $output");
}

sub addComment {
	my $input_file = shift;
	my $output_image = shift;
	my $intext = "NODATA";

	unless (-f $input_file) {
		$intext = "SDAT: No OCR file $input_file\n";
		warn($input_file);
	}

	if (-z $input_file) {
		$intext = "SDAT: No OCR text in file $input_file\n";
		warn($input_file);
	}

	if ( -f $input_file ){
		open(TEXT, "<$input_file") or die($!);
		$intext = "";
		while(<TEXT>) {
			$intext .= $_;
		}
		close(TEXT);
		$intext =~ s/"/\\"/g;
	}

	warn("Could not write EXIF tag\n") if system("exiv2", "-M", "set Exif.Photo.UserComment charset=Ascii \"$intext\"", $output_image);
}


sub get_device {
	my $DEVICE=`scanimage -L | awk '{ print \$2 }'`;
	$DEVICE =~ s/\`//;
	$DEVICE =~ s/\'//;
	$DEVICE =~ s/\n//;
	print "Using Device: $DEVICE\n";
	return $DEVICE;
}

sub exe {
	my $cmd = shift;
	if ( -f "./env.sh") {
		print "Using environment source\n";
		die("Could not execute $cmd, quitting\n") if system("source ./env.sh && $cmd");
	} else {
		die("Could not execute $cmd, quitting\n") if system($cmd);
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

1;

