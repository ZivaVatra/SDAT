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




