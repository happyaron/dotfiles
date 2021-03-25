#!/usr/bin/python3
'''
Tool for setting DPI of Microsoft® Classic IntelliMouse®

Modified from the original class to better handle usb device claims:
https://gist.github.com/K-Visscher/22561ca69a64339a7383d67db6e79818
'''

import usb.core
import usb.util

VID = 0x045E
PID = 0x0823

DPI_WRITE_PROPERTY = 0x96

WRITE_REPORT_ID = 0x24
WRITE_REPORT_LENGTH = 0x20

INTERFACE = 0x01

class IntelliMouse():
	def __init__(self):
		self.device = usb.core.find(idVendor=VID, idProduct=PID)
		if self.device is None:
			raise ValueError("couldn't find the intellimouse...")

	def __enter__(self):
		'''
		gain control from kernel driver
		'''
		for config in self.device:
			self.reattach = [False] * config.bNumInterfaces
			for i in range(config.bNumInterfaces):
				if self.device.is_kernel_driver_active(i):
					self.device.detach_kernel_driver(i)
					self.reattach[i] = True
		self.device.set_configuration()

	def __exit__(self, exc_type, exc_val, exc_tb):
		'''
		give control back to kernel driver
		'''
		usb.util.dispose_resources(self.device)
		for config in self.device:
			for i in range(config.bNumInterfaces):
				if self.reattach[i] and not self.device.is_kernel_driver_active(i):
					self.device.attach_kernel_driver(i)

	def __write_property(self, property, data):
		if not isinstance(property, int):
			raise TypeError("please make sure to pass a integer for the property argument...")
		if not isinstance(data, list) or not all(isinstance(x, int) for x in data):
			raise TypeError("please make sure to pass a list of integers for the data argument...")
		report = self.__pad_right([WRITE_REPORT_ID, property, len(data)] + data, WRITE_REPORT_LENGTH)
		self.device.ctrl_transfer(0x21, 0x09, 0x03 << 8 | WRITE_REPORT_ID, INTERFACE, report)


	def __pad_right(self, data, until):
		if not isinstance(data, list) or not all(isinstance(x, int) for x in data):
			raise TypeError("please make sure to pass a list of integers for the data argument...")
		if not isinstance(until, int):
			raise TypeError("please make sure to pass a integer for the until argument...")
		if until <= 0:
			raise ValueError("please pass a positive integer for the until argument...")
		if len(data) >= until:
			return
		return data + ((until - len(data)) * [0x00])

	def set_dpi(self, dpi):
		'''
		take a single integer between (400, 3200), step is 200
		'''
		if not isinstance(dpi, int):
			raise TypeError("please make sure to pass an integer...")
		if dpi % 200 != 0 or not (dpi >= 400 and dpi <= 3200):
  			raise ValueError("please make sure to pass a valid value (dpi % 200 == 0 and (dpi >= 400 and dpi <= 3200))")
		self.__write_property(DPI_WRITE_PROPERTY, [0x00] + list(dpi.to_bytes(2, byteorder="little")))
		print("Sending DPI value {} to device...".format(dpi))

if __name__ == "__main__":
	'''
	requires root privileges
	'''
	import sys
	
	try:
		DPI = int(sys.argv[1])
	except:
		# Recommended value of this mouse is 3200,
		# although some older ones default to 1600.
		DPI = 3200

	m = IntelliMouse()
	with m:
		m.set_dpi(DPI)