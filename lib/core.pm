#package ::core;
use strict;
use warnings;

#use Exporter qw(import);
#our @EXPORT_OK = qw(get_device exe bgexe ocrit topng addComment scanit_adf);

# OCR commands for ADF
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
	   exec("scanimage -v -p --format=tiff $extraopts -d \"$device\" --resolution $resolution > $o_folder/$o_pattern") or die ("could not scan!\n");
	}

	my $time = time();
	print "Waiting for scanning to finish\n";
	sleep 1;
	while ((time() - $time) < 60 ) {
		if ( waitpid($pid,1) == -1 ) {
			return(0);
		}
		sleep 1;
	}

	print "Error! Timeout exceeded! Killing and continuing...\n";
	kill("TERM",$pid);
	sleep 1;
	kill("KILL",$pid); #Scanimage will abort if it gets two SIGTERM's
	return(0);
}

# OCR commands

sub ocrit {
	my $input_image = shift;
	my $output_text = shift;
	return bgexe("tesseract $input_image $output_text --tessdata-dir /usr/share/tesseract-ocr/ -l eng ");
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

