/* To compile:
 *
 *  cc -L/lib/libusb-1.0.so.0 -lusb-1.0 -lm -I /usr/include/libusb-1.0 -I /usr/include/libusb-1.0/  -o ./reset-epsonv330 ./reset-epsonv330.c 
 *
 *  Based on code taken from here: https://bugzilla.redhat.com/show_bug.cgi?id=723696
 */

/* reset-hp5590: code to reset scanner on usb bus, releasing the usbfs driver attached at boot-up */
	#include <stdio.h>
	#include <libusb.h>

int main(void)
{

        libusb_device_handle *dev;
		
	uint16_t vendor_id;
	uint16_t product_id;
		
        int r;

/*parameters for hp5590 scanner*/		
//		vendor_id = 0x03f0;
//		product_id = 0x1705;

/*parameters for Epson v330 scanner (epkowa)*/
	vendor_id = 0x04b8;
	product_id = 0x0142;
	char device[] = "Epson V330"; //HP5590 

        r = libusb_init(NULL);
        if (r < 0)
            return r;
	
        dev = libusb_open_device_with_vid_pid(NULL, vendor_id, product_id );
        if (dev == NULL)
	        return 16;
		printf("Opened %s device handle\n",device);
		
		r = libusb_reset_device(dev);
		if(r == 0) { printf("Successful reset of device %s\n",device); }
		libusb_close(dev);
	    libusb_exit(NULL);
		printf("Returning with code %d\n",r);
        return r;
}
