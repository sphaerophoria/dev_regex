obj-m  := dev_regex.o
dev_regex-y := dev_regex_interface.o ../zig-out/bin/dev_regex_impl.o
ccflags-y := -I$(PWD)/../include

FORCE:
$(PWD)/../zig-out/bin/dev_regex_impl.o: FORCE
	cd $(PWD)/../ && zig build driver
