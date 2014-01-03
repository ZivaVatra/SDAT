SDAT
====

This is a script for archival of Documents/Bills/Invoices/etc...
It scans the page, runs OCR on the text, and saves the text to the comment field in the metadata

This allows indexing engines (e.g. Desktop search) to know what text the document contains, allowing
for easier searching, while keeping the original text+format as an image scan.
It saves a PNG file into the $FINALDST folder

For full information, see the original web page:
	http://www.ziva-vatra.com/index.php?aid=71&id=U29mdHdhcmU=

----

Requirements:
    tesseract (OCR)
    sane-tools (SCANNING)
    Exiv2 image metadata library (for adding text to comment field)
	imageMagick tools (FORMAT CONVERSION)

<pre>
Usage:
	* There must be a "./tmp" and "./scans" folder in the CWD.
	
	* You have to edit the script $DEVICE variable, and put in which device you want to use. For example, if I run "scanimage -L":
	 	device `v4l:/dev/video0' is a Noname UNKNOWN/GENERIC virtual device
	 	device `epkowa:interpreter:001:006' is a Epson Perfection V330 Photo flatbed scanner
	  Then use the bits in the quotes as your device. 
	
	* The script will auto-detect rotation of script, so you don't have to worry about it
	
	* Run the script as follows:
		./SDAT.sh $Name_of_scan

Known bugs:
	* Script will accept a blank file name, which it shouldn't.
	* Script won't check and create the needed temp folders
</pre>
