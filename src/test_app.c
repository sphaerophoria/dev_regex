#include "dev_regex_ioctl.h"
#include <unistd.h>
#include <fcntl.h>
#include <sys/ioctl.h>
#include <stdio.h>
#include <stdbool.h>

int main(void) {
	int fd = open("/dev/regex", O_RDWR);

	char query_str[] = "hello\nagain goodbye\nagain\nhello again\ngoodbye again\n";
	write(fd, query_str, sizeof(query_str));

	char regex_str[] = "again$";
	struct regex_set_arg arg = {
		.data = regex_str,
		.len = sizeof(regex_str) - 1,
	};
	ioctl(fd, REGEX_SET, &arg);

	char buf[sizeof(query_str)] = {0};
	printf("Reading\n");

	int num_bytes_read = 1;
	while (num_bytes_read != 0) {
		num_bytes_read = read(fd, buf, sizeof(query_str));
		printf("num bytes read: %d\n", num_bytes_read);

		printf("Matched: ");
		fwrite(buf, 1, num_bytes_read, stdout);
		printf("\n");
	}

	close(fd);

	return 3;
}
