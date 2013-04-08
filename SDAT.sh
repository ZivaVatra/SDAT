#!/bin/bash

# SDAT - Scanned document archival tool

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

# Current Limitations:
#	* The language is hardcoded to english for OCR
#	* metadata uses ASCII (not sure if possible to use unicode)
#

TPATH=./tmp/

function scanit {
        scanimage  -p --format=tiff --mode $1 --resolution $2 > $TPATH/$3
}

function 600dpi_col {
        scanit color 600 $1;
}

function 600dpi_gr {
        scanit gray 600 $1;
}

function 1200dpi_gr {
        scanit gray 1200 $!;
}

function ocrit {
         tesseract $TPATH/$1 $TPATH/$2 -l eng
}

 function topng {
         convert -compress Zip $TPATH/$1 $TPATH/$2;
}

 function addComment {
         exiv2 -M"set Exif.Photo.UserComment charset=Ascii `cat $TPATH/$1`" $TPATH/$2
}


function waituntildone {
	while true; do
		ps $1 2>&1>/dev/null
		if [[ $? != 0 ]]; then
			break;
		fi
		sleep 2;
	done
}

RANDSTR=`head -c 20 /dev/urandom  | md5sum | cut -d' ' -f 1`
FINALDST="./scans/"
NAME=$1; #filename
read -p  "Hit enter to scan (filename: $NAME ), CTRL-C to cancel"

#1. Scan the image (gray for OCR)
600dpi_gr scan_gr.$RANDSTR.tif
sleep 0.5s
#2. Scan the colour image we will store
600dpi_col scan_col.$RANDSTR.tif &
SCANPID=$!; #the pid of the scanner process

#3 ocr the image
ocrit scan_gr.$RANDSTR.tif scan_txt.$RANDSTR

#4 wait for the color scan to finish
waituntildone $SCANPID
	
#ok, all done! Now convert to png and add text
topng scan_col.$RANDSTR.tif $NAME.png

addComment scan_txt.$RANDSTR.txt $NAME.png

mv -v  $TPATH/$NAME.png $FINALDST/

rm -v $TPATH/*$RANDSTR*
